# Stellar Testnet Synchronization Analysis

**Date:** 2026-07-17
**Last updated:** 2026-07-17 20:30h
**Container:** stellar-testnet (stellar/quickstart:testing)
**Network:** Testnet ("Test SDF Network ; September 2015")
**Core Version:** v27.1.0
**Horizon Version:** devel

---

## 1. General Container Architecture

The container uses **supervisord** to manage multiple processes. The entrypoint is `/start` (bash script) which:

1. Copies default configurations to persistent volumes (first run only)
2. Initializes PostgreSQL and creates the `horizon` database
3. Initializes Stellar Core (new-db)
4. Initializes Horizon (db init)
5. Stops the temporary PostgreSQL
6. Runs `supervisord`, which manages the services

### Services managed by supervisor:

| Service | Binary | Port | Function |
|---------|--------|------|----------|
| **stellar-core (node)** | `/usr/bin/stellar-core --conf ...` | 11625 (P2P), 11626 (HTTP) | SCP consensus, ledger synchronization, P2P |
| **stellar-core (Horizon captive core)** | `/usr/bin/stellar-core --conf ... --metadata-output-stream fd:3` | 11725 (P2P), 11726 (HTTP) | Horizon child process for data ingestion |
| **Horizon** | `/usr/bin/stellar-horizon` | 8001 (HTTP), 6060 (admin) | RESTful API, ledger data ingestion into PostgreSQL |
| **PostgreSQL** | `/usr/lib/postgresql/14/bin/postgres` | 5432 | Horizon database |
| **nginx** | `/usr/sbin/nginx` | 8000 (public) | Reverse proxy: `/` -> Horizon, `/friendbot` -> external, `/rpc` -> RPC |

### Ports exposed on the host:
- `8000:8000` — nginx (proxy to Horizon)
- `11625:11625` — Core P2P (connection with validators)
- `11626:11626` — Core HTTP (admin/info)

---

## 2. Synchronization Flow (Step by Step)

After the container starts, the synchronization process follows these steps:

### Phase 1: Service Initialization
1. Supervisord starts `nginx` and `stellar-core` (node)
2. Core node starts syncing from genesis — downloads **history** and **buckets** from the archives
3. Supervisord starts `postgresql`
4. Supervisord starts `horizon`
5. Horizon checks whether the Core node has already reached the minimum ledger (`core_latest_ledger > 5`)

### Phase 2: Core Node — Catching Up
The Core node runs two processes in parallel:
- **"node" process** (port 11626): Main synchronization via P2P + archives
- **"horizon" process** (port 11726): Horizon captive core instance

**Logs observed for the node:**
```
Catching up to ledger 3663423: downloading ledger files 247/247 (100%)
Download & apply checkpoints: num checkpoints left to apply:247 (0% done)
```

**Logs observed for the horizon (captive core):**
```
Joining SCP; Catching up to ledger 3647651:
  downloading and verifying buckets: 37/37 (100%)
  Applying buckets 100%
  Download & apply checkpoints: num checkpoints left to apply:1
```

### Phase 3: Horizon Captive Core
Horizon manages its own **captive core** instance (`ENABLE_CAPTIVE_CORE_INGESTION=true`). This instance:
- Uses a separate config: `/opt/stellar/horizon/etc/stellar-captive-core.cfg`
- Own HTTP port: 11726 (loopback only)
- Own P2P port: 11725
- Own SQLite database: `/opt/stellar/horizon/captive-core/stellar.db`
- Own buckets: `/opt/stellar/horizon/captive-core/captive-core/buckets/`

### Phase 4: Horizon Ingest
When the captive core reaches a valid ledger, Horizon:
1. Reads ledger metadata via pipe (`--metadata-output-stream fd:3`)
2. Processes transactions, operations, effects, accounts, etc.
3. Persists to PostgreSQL (`horizon` database)
4. Updates `ingest_latest_ledger` in the `/` endpoint

---

## 3. External Requests (Where and What)

### 3.1. History Archives (historical data downloads)

**Base URLs:**
- `https://history.stellar.org/prd/core-testnet/core_testnet_001`
- `https://history.stellar.org/prd/core-testnet/core_testnet_002`
- `https://history.stellar.org/prd/core-testnet/core_testnet_003`

**Files downloaded:**

| Type | Format | Example | Content |
|------|--------|---------|--------|
| Ledger headers | JSON | `history-00/37/a8/history-0037a87f.json` | Checkpoint headers (64 ledgers) |
| Transaction history | XDR | `transaction/00/37/a8/transactions-0037a87f.xdr` | Grouped transactions |
| Buckets | XDR | `bucket-022e182f76b419ae6e03ee5c99ac10cba115ced44e8329e17bf8fb9ea093e17a.xdr` | Complete ledger state (accounts, trustlines, offers, etc.) |
| Bucket indexes | Index | `bucket-....index` | Indexes for bucket lookups |
| Results | XDR | `results-....xdr` | Transaction results |
| SCVal | XDR | `scval-....xdr` | Soroban values (smart contracts) |

### 3.2. P2P (Real-time Consensus)

**Destinations:**
- `core-testnet1.stellar.org:11625`
- `core-testnet2.stellar.org:11625`
- `core-testnet3.stellar.org:11625`

**Protocol:** Stellar SCP (SCP — Stellar Consensus Protocol) over TCP port 11625

**Data exchanged:**
- SCP envelopes (nomination, ballot, externalize)
- Mempool transactions
- Peer discovery messages (ID, version, network)

### 3.3. Friendbot (only when enabled)

**URL:** `https://friendbot.stellar.org`

**Function:** Proxied by nginx at `/friendbot` — used to create test accounts on the testnet.

### 3.4. Internal monitoring (no external egress)
- `curl http://localhost:11726/info` — captive core status (Horizon)
- `curl http://localhost:11626/info` — core node status
- `curl http://localhost:8001` — Horizon health check

---

## 4. Database Load

### 4.1. PostgreSQL (Horizon — processed/structured data)

**Total size:** ~39MB (still syncing)

**Main tables and their sizes:**

| Table | Size | Content |
|-------|------|---------|
| `accounts_signers` | 1427 MB | Account signers (largest table — every multi-sig adds to it) |
| `accounts` | 872 MB | Current state of all accounts |
| `history_transactions` | 590 MB | Processed transaction history |
| `trust_lines` | 279 MB | Trustlines (trust in assets) |
| `accounts_data` | 220 MB | Account data entries |
| `history_operations` | 182 MB | Individual operations within transactions |
| `offers` | 34 MB | Live offers (order book) |
| `history_effects` | 33 MB | Operation effects |
| `exp_asset_stats` | 34 MB | Asset statistics |
| `history_ledgers` | 17 MB | Ledger headers |

**Note:** The history tables (`history_*`) store immutable data for API queries. The "live" tables (`accounts`, `offers`, `trust_lines`) reflect the current state.

### 4.2. SQLite (Core Node)

**Files in `/opt/stellar/core/`:**
- `stellar.db` (21 MB) — Core node ledger data
- `stellar-misc.db` (0.2 MB) + WAL (41 MB) — Miscellaneous data (likely quorum state, peers, etc.)
- `buckets/` (4.5 GB) — XDR buckets of the complete ledger state

### 4.3. SQLite (Horizon Captive Core)

**Files in `/opt/stellar/horizon/captive-core/`:**
- `stellar.db` (21 MB) — Captive core ledger
- `stellar-misc.db` (0.06 MB) + WAL (2.8 MB) — Misc
- `bucket-cache/` (4 KB) — Bucket cache

### 4.4. Total storage
```
/opt/stellar/            = 14 GB
├── core/                = 4.6 GB  (main node + buckets)
├── horizon/captive-core = 4.6 GB  (captive core + buckets)
└── postgresql/          = 39 MB   (PostgreSQL data)
```

---

## 5. Processing Pipeline: Data Flow

```
History Archives (SDF)
  https://history.stellar.org/prd/core-testnet/
         │
         ├────────────────────────────────────────┐
         ▼                                        ▼
  ┌──────────────┐                        ┌──────────────┐
  │ Core Node    │                        │ Captive Core │
  │ (main)       │                        │ (Horizon)    │
  │              │                        │              │
  │ Downloads:   │                        │ Downloads:   │
  │ - ledgers    │                        │ - buckets    │
  │ - buckets    │                        │ - ledgers    │
  │ - txs        │                        │              │
  │              │                        │              │
  │ Ports:       │                        │ Ports:       │
  │  11625 (P2P) │                        │  11725 (P2P) │
  │  11626 (HTTP)│                        │  11726 (HTTP)│
  └──────┬───────┘                        └──────┬────────┘
         │                                       │
         │ P2P consensus (SCP)                   │ metadata pipe
         │                                       ▼
         │                               ┌──────────────┐
         │                               │ Horizon       │
         │                               │              │
         │                               │ Reads        │
         │                               │ metadata via │
         │                               │ fd:3         │
         │                               │              │
         │                               │ Processes:   │
         │                               │ - txs        │
         │                               │ - operations │
         │                               │ - effects    │
         │                               │ - accounts   │
         │                               └──────┬───────┘
         │                                       │
         │                                       ▼
         │                               ┌──────────────┐
         │                               │ PostgreSQL   │
         │                               │ (horizon     │
         │                               │  database)   │
         │                               │              │
         │                               │ 33 tables    │
         │                               │ ~39 MB       │
         │                               └──────────────┘
         │
         ▼
  ┌──────────────┐
  │ Local SQLite │
  │ (core node)  │
  │              │
  │ stellar.db   │
  │ 21 MB        │
  │ buckets 4.5GB│
  └──────────────┘
```

### 5.1. What goes to the **Core Node** (SQLite)
- Ledger headers and sequence numbers
- Buckets: complete ledger state (accounts, trustlines, offers, data, signers)
- Transactions and results
- Quorum/SCP information
- Validator configuration

### 5.2. What goes to the **Captive Core** (SQLite)
- Buckets required to rebuild state
- Ledgers for processing
- **Does not participate in P2P consensus** (ingestion only)
- Managed by Horizon

### 5.3. What goes to the **Horizon** (PostgreSQL)
- Processed and structured data in 33 tables:
  - **Accounts** (`accounts`, `accounts_signers`, `accounts_data`)
  - **Transactions** (`history_transactions`, `history_transaction_participants`)
  - **Operations** (`history_operations`, `history_operation_participants`)
  - **Effects** (`history_effects`) — each operation generates N effects
  - **Assets** (`history_assets`, `exp_asset_stats`, `asset_contracts`)
  - **Trades** (`history_trades`, `history_trades_60000`)
  - **Claimable Balances** (`claimable_balances`, `claimable_balance_claimants`)
  - **Liquidity Pools** (`liquidity_pools`, `history_liquidity_pools`)
  - **Offers** (`offers`)
  - **Fee Stats** (embedded in the API)
  - **Contract data** (Soroban: `contract_asset_balances`, `contract_asset_stats`)
  - **Filters** (`account_filter_rules`, `asset_filter_rules`)
  - **Migrations** (`gorp_migrations`) — schema control
  - **Key-value** (`key_value_store`) — internal configuration

---

## 6. Differences Between the Two Core Processes

| Characteristic | Core Node (PID 118) | Captive Core (PID 3929) |
|---------------|---------------------|------------------------|
| **Config** | `/opt/stellar/core/etc/stellar-core.cfg` | `/opt/stellar/horizon/etc/stellar-captive-core.cfg` |
| **Database** | SQLite `/opt/stellar/core/stellar.db` | SQLite `/opt/stellar/horizon/captive-core/stellar.db` |
| **Buckets** | `/opt/stellar/core/buckets/` (4.5 GB) | `/opt/stellar/horizon/captive-core/captive-core/buckets/` (same size) |
| **P2P port** | 11625 | 11725 |
| **HTTP port** | 11626 | 11726 |
| **Participates in SCP?** | Yes | No |
| **Output metadata** | Normal | Pipe fd:3 to Horizon |
| **Started by** | supervisord (service) | Horizon (fork/exec) |
| **Purpose** | Consensus + sync | Provide ledger data for ingestion |

---

## 7. Observations on Synchronization Behavior

1. **Data duplication**: The Core node and the Horizon captive core download buckets separately (~4.5 GB each). Both come from the same SDF history archives.

2. **Catchup strategy**: The Core node uses `CATCHUP_RECENT=100` (configured in stellar-core.cfg), which means it tries to reach the last 100 ledgers before entering consensus mode.

3. **Checkpoints**: Every 64 ledgers, a checkpoint is generated. `CHECKPOINT_FREQUENCY=64` in Horizon.

4. **Ingestion**: `INGEST_DISABLE_STATE_VERIFICATION=True` — state verification is skipped to speed up the initial synchronization.

5. **State verification**: `ENABLE_CAPTIVE_CORE_INGESTION=true` + `CAPTIVE_CORE_USE_DB=true` — Horizon uses a captive core with a SQLite database to rebuild state, instead of calling the core node HTTP API.

6. **Rate limit**: `PER_HOUR_RATE_LIMIT=72000` — 72,000 requests per hour on Horizon.

7. **Observed latency**: It took ~3 minutes for the captive core to reach the target ledger and for Horizon to start ingesting data.

---

## 8. Horizon API Endpoints (exposed via nginx on port 8000)

| Route | Description |
|-------|-------------|
| `/` | Root — ledger info and HATEOAS links |
| `/accounts` | List accounts |
| `/accounts/{id}` | Account details |
| `/transactions` | Transaction history |
| `/operations` | Operations |
| `/effects` | Effects |
| `/ledgers` | Ledgers |
| `/assets` | Assets |
| `/trades` | Trades |
| `/offers` | Offers |
| `/payments` | Payments |
| `/claimable_balances` | Claimable balances |
| `/liquidity_pools` | Liquidity pools |
| `/fee_stats` | Fee statistics |
| `/order_book` | Order book |
| `/paths/strict-receive` | Path finding |
| `/paths/strict-send` | Path finding |

---

## 9. Key Configurations

**Horizon (`horizon.env`):**
```bash
DATABASE_URL="postgres://stellar:<pass>@localhost/horizon"
STELLAR_CORE_URL="http://localhost:11726"
ENABLE_CAPTIVE_CORE_INGESTION="true"
CAPTIVE_CORE_USE_DB=true
INGEST="true"
CHECKPOINT_FREQUENCY=64
INGEST_DISABLE_STATE_VERIFICATION=True
HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
```

**Core Node (`stellar-core.cfg`):**
```ini
HTTP_PORT=11626
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/core/stellar.db"
CATCHUP_RECENT=100
```

**Captive Core (`stellar-captive-core.cfg`):**
```ini
HTTP_PORT=11726
PEER_PORT=11725
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/horizon/captive-core/stellar.db"
```

---

## 10. Quantitative Analysis of the Synchronized State

### 10.1. Bucket Content (complete network state)

Data obtained from stellar-core metrics (`/metrics`) during execution:

| Entry Type | Quantity | Total Size (bytes) | % of State |
|------------|----------|--------------------|------------|
| PERSISTENT_CONTRACT_DATA | 4.360.649 | 740.016.048 | 40,2% |
| ACCOUNT | 2.952.227 | 374.514.724 | 20,3% |
| CONTRACT_CODE | 25.168 | 326.714.560 | 17,7% |
| TTL (Time-To-Live) | 4.552.345 | 217.381.504 | 11,8% |
| TRUSTLINE | 335.370 | 45.534.520 | 2,5% |
| DATA (account data) | 340.684 | 49.321.276 | 2,7% |
| OFFER | 62.150 | 8.689.832 | 0,5% |
| TEMPORARY_CONTRACT_DATA | 167.877 | 24.684.924 | 1,3% |
| CLAIMABLE_BALANCE | 9.242 | 2.406.644 | 0,1% |
| LIQUIDITY_POOL | 2.687 | 422.480 | 0,02% |
| CONFIG_SETTING | 55 | 9.128 | <0,01% |
| **Total** | **~13.808.454** | **~1.840.929.876** | **100%** |

**Total size on disk:** ~4.4 GB (compressed/differential)
**Total uncompressed size:** ~1.84 GB

### 10.2. Buckets by Level (Merge Levels)

The stellar-core bucket system organizes buckets into levels (0-6):

- **Level 0 (base):** ~677 merges — small buckets with recent data
- **Level 1:** ~2.797 merges
- **Level 2:** ~758 merges
- **Level 3:** ~208 merges
- **Level 4:** ~63 merges
- **Level 5:** ~18 merges
- **Level 6 (snap):** ~4 merges — large buckets with complete snapshots

**Top 5 largest buckets (uncompressed XDR files):**

| File | Size |
|------|------|
| bucket-ff26b4f5...7efd.xdr | 785 MB |
| bucket-eb7625ce...4b72.xdr | 610 MB |
| bucket-d8522ede...2d730.xdr | 600 MB |
| bucket-8a27deda...b125.xdr | 452 MB |
| bucket-b2a2c09a...d09b.xdr | 355 MB |

### 10.3. SQLite Storage

**Core Node (heavy SQLite WAL):**
| File | Size |
|------|------|
| stellar.db | 21 MB (compressed data) |
| stellar.db-wal | 44 MB (Write-Ahead Log — active writes) |
| stellar.db-shm | 96 KB (Shared Memory) |
| stellar-misc.db | 208 KB |
| stellar-misc.db-wal | 40 MB |

**Captive Core (structurally identical SQLite):**
| File | Size |
|------|------|
| stellar.db | 21 MB |
| stellar.db-wal | 40 MB |
| stellar-misc.db | 64 KB |
| stellar-misc.db-wal | 8,1 MB |

### 10.4. PostgreSQL Database (Horizon)

**Total database:** 3.955 MB (data + indexes)
**WAL:** 417 MB (16 MB files each)

**Actual sizes per table (including indexes and TOAST):**

| Table | Total (data + indexes) | Data (heap) | Indexes/TOAST | % of DB |
|-------|------------------------|-------------|---------------|---------|
| accounts_signers | 1.428 MB | 429 MB | 999 MB | 36,1% |
| accounts | 873 MB | 499 MB | 374 MB | 22,1% |
| history_transactions | 679 MB | 357 MB | 322 MB | 17,2% |
| trust_lines | 279 MB | 108 MB | 171 MB | 7,1% |
| accounts_data | 220 MB | 95 MB | 126 MB | 5,6% |
| history_operations | 210 MB | 190 MB | 20 MB | 5,3% |
| history_operation_participants | 48 MB | 21 MB | 27 MB | 1,2% |
| history_transaction_participants | 38 MB | 17 MB | 21 MB | 1,0% |
| history_effects | 37 MB | 26 MB | 11 MB | 0,9% |
| remaining (24 tables) | ~165 MB | ~90 MB | ~75 MB | 4,2% |

**Record counts processed by Horizon:**
- **Accounts:** 2.909.585
- **Transactions:** 236.368
- **Operations:** 361.670
- **Ledgers ingested:** 21.593 (range: 3.629.312 to 3.650.904)

---

## 11. Detailed Processing Pipeline — The Data Path

```
                        HISTORY ARCHIVES (SDF)
                     https://history.stellar.org/
                              |
               ┌──────────────┴──────────────┐
               ▼                              ▼
    ┌──────────────────┐          ┌──────────────────┐
    │   CORE NODE      │          │  CAPTIVE CORE    │
    │  (PID 118)       │          │  (PID 3929)      │
    │                  │          │                  │
    │ 1. Downloads     │          │ 1. Downloads     │
    │    ledger files  │          │    ledger files  │
    │    (JSON)        │          │    (JSON)        │
    │                  │          │                  │
    │ 2. Downloads     │          │ 2. Downloads     │
    │    buckets (XDR) │          │    buckets (XDR) │
    │    via HTTP      │          │    via HTTP      │
    │                  │          │                  │
    │ 3. Verifies      │          │ 3. Verifies      │
    │    SHA256 hashes │          │    SHA256 hashes │
    │                  │          │                  │
    │ 4. Applies       │          │ 4. Applies       │
    │    checkpoints   │          │    checkpoints   │
    │    (tx replay)   │          │    (tx replay)   │
    │                  │          │                  │
    │ 5. SCP Consensus │          │ 5. (NO SCP)      │
    │    (P2P)         │          │    replay only   │
    └──────┬───────────┘          └────────┬─────────┘
           │                               │
           │ P2P: 11625                    │ Pipe: fd:3
           │ HTTP: 11626                   │ (metadata)
           │                               ▼
           │                     ┌──────────────────┐
           │                     │    HORIZON       │
           │                     │  (PID 168)       │
           │                     │                  │
           │                     │ Reads metadata   │
           │                     │ from captive     │
           │                     │ core via pipe    │
           │                     │ (stdout ledger   │
           │                     │ metadata)        │
           │                     │                  │
           │                     │ For each ledger: │
           │                     │  - Meta (header) │
           │                     │  - TxSet         │
           │                     │  - Tx processing │
           │                     │  - Operations    │
           │                     │  - Effects       │
           │                     │  - Account       │
           │                     │    changes       │
           │                     │  - Trades        │
           │                     │  - etc.          │
           │                     └────────┬─────────┘
           │                              │
           │                              ▼
           │                     ┌──────────────────┐
           │                     │   PostgreSQL     │
           │                     │  Port 5432       │
           │                     │                  │
           │                     │ 33 tables        │
           │                     │ 3.955 MB         │
           │                     └──────────────────┘
           │
           ▼
    ┌──────────────────┐
    │    SQLite        │
    │  stellar.db      │
    │  21 MB + WAL     │
    │                  │
    │ buckets/         │
    │  4.4 GB (79 .xdr)│
    └──────────────────┘
```

### 11.1. Breakdown: What each component processes

**Core Node (stellar-core PID 118):**
- **Checkpoint download:** Downloads JSON ledger header and transaction files from the history archive
- **Bucket download:** Downloads XDR files with state snapshots (accounts, offers, trustlines, contract data)
- **Cryptographic verification:** SHA256 of each bucket, SCP signature verification
- **Bucket merge:** Combines lower-level buckets into higher levels (levels 0 to 6)
- **Transaction replay:** Applies checkpoint transactions to advance state
- **SCP Consensus:** Participates in the consensus protocol with SDF validators via P2P

**Captive Core (another stellar-core, child of Horizon):**
- **Same steps as the Core Node**, except it does NOT participate in SCP
- **Single purpose:** Provide ledger metadata to Horizon via pipe (`--metadata-output-stream fd:3`)
- **Separate ports:** 11725 (P2P, no peers), 11726 (HTTP, loopback)

**Horizon (stellar-horizon PID 168):**
- **Receives metadata from the captive core** via pipe (process stdout)
- **For each new ledger meta received:**
  1. Inserts `history_ledgers` (header, timestamp, hash)
  2. Inserts `history_transactions` + participants
  3. Processes each operation → `history_operations` + participants
  4. Generates effects → `history_effects`
  5. Updates current state: `accounts`, `accounts_signers`, `accounts_data`, `trust_lines`, `offers`
  6. Processes trades → `history_trades`
  7. Processes claimable balances → `claimable_balances`, `claimable_balance_claimants`
  8. Processes liquidity pools → `liquidity_pools`
  9. Processes Soroban contracts → `contract_asset_balances`, `contract_asset_stats`, `asset_contracts`
  10. Updates `exp_asset_stats`

### 11.2. Why two core processes?

Horizon uses **Captive Core Ingestion** (`ENABLE_CAPTIVE_CORE_INGESTION=true`) to:
1. **Isolation**: Ingestion does not interfere with the main core's consensus
2. **Performance**: The captive core can be configured independently (ports, database, buckets)
3. **Consistent snapshot**: The captive core provides a consistent point of view of the data

**Cost:** Storage duplication (~4.6 GB of buckets each) and redundant processing.

---

## 12. Network and Processing Metrics (from the Core Node)

### 12.1. SCP (Consensus)

| Metric | Value |
|--------|-------|
| SCP envelopes received | 4.713 |
| SCP envelopes signed | 467 |
| SCP envelopes validated OK | 4.298 |
| SCP nominate timeouts | 115 |
| SCP prepare timeouts | 115 |
| Ballot blocked on txset | 115 |

### 12.2. Overlay (P2P)

| Metric | Value |
|--------|-------|
| Bytes read (network) | 4,56 MB |
| Bytes written (network) | 1,90 MB |
| Messages read | 7.134 |
| Messages written | 5.012 |
| Authenticated connections | 3 |
| Established connections | 225 |
| Rejected connections | 221 |
| SCP messages broadcast | 4.063 |
| Flood unique received | 906.252 |

### 12.3. History Archive Downloads

| Metric | Value |
|--------|-------|
| Total throughput (bytes) | 18.082.855 (~18 MB) |
| History check success | 3 |
| Ledger check success | 3 |
| Bucket batch add time | 4.822 calls |
| Objects added to buckets | 158.534 |

### 12.4. Ledger Processing

| Metric | Value |
|--------|-------|
| Ledgers closed | 4.822 |
| Ledger apply successes | 39.129 |
| Ledger apply failures | 7.742 |
| Transactions applied | 46.871 |
| Operations applied | 71.502 |
| Soroban successes | 30.852 |
| Soroban failures | 356 |
| Avg txs/ledger | ~9,7 |
| Avg ops/ledger | ~15,0 |

### 12.5. Soroban (Smart Contracts)

| Metric | Value |
|--------|-------|
| Host functions executed | 31.194 |
| CPU instructions (total) | ~261 billion |
| Memory used | ~81,9 GB (total accumulated) |
| Contract code entries in memory | 4.668 |
| Contract code size in memory | ~2,37 GB |
| Contract data entries in memory | 1.311.996 |
| Contract data size in memory | ~299 MB |
| Compiled code entries | 4.668 |
| Total compilation time | 77 units |
| Read entries | 165.732 |
| Write entries | 52.866 |

---

## 13. Synchronization Gap Analysis

During execution, a consistent difference between the Core Node and the Captive Core was observed:

| Instance | Current Ledger | Progress | Ledgers remaining |
|----------|---------------|----------|-------------------|
| Core Node | 3.653.467 | ~70,8% | ~157 checkpoints |
| Captive Core | 3.651.297 | ~64,3% | ~191 checkpoints |
| Horizon (ingest) | 3.651.291 | — | trailing captive |

**Core vs Captive gap:** 2.170 ledgers
**Captive vs Horizon gap:** 6 ledgers (normal processing latency)

The Core node is about **2.100 ledgers ahead** of the captive core because:
1. The Core node started first (PID 118, started 00:22:42)
2. The Captive core started later (PID 3929, started 00:26:14) — ~3,5 minutes later
3. Both download buckets independently (same source)
4. Horizon must wait for the captive core to catch up before ingesting new data

---

## 14. Complete Network Topology

```
HOST: localhost
├── :8000 → nginx (reverse proxy)
│   ├── / → Horizon (127.0.0.1:8001)
│   ├── /friendbot → friendbot.stellar.org (external)
│   └── /rpc → Stellar RPC (127.0.0.1:8003) [not active in this setup]
│
├── :11625 → Core Node P2P → core-testnet{1,2,3}.stellar.org:11625
├── :11626 → Core Node HTTP (admin/info)
│
└── (internal)
    ├── 127.0.0.1:11725 → Captive Core P2P (no external peers)
    ├── 127.0.0.1:11726 → Captive Core HTTP (consumed by Horizon)
    ├── 127.0.0.1:5432 → PostgreSQL (consumed by Horizon)
    ├── 127.0.0.1:8001 → Horizon API (nginx + captive core consumer)
    ├── 127.0.0.1:6060 → Horizon Admin
    ├── 127.0.0.1:9001 → Supervisord HTTP
    └── 127.0.0.11:44005 → Docker DNS

EXTERNAL:
├── history.stellar.org (HTTPS) — archive downloads
│   ├── /prd/core-testnet/core_testnet_001/
│   ├── /prd/core-testnet/core_testnet_002/
│   └── /prd/core-testnet/core_testnet_003/
├── core-testnet1.stellar.org:11625 (P2P SCP)
├── core-testnet2.stellar.org:11625 (P2P SCP)
├── core-testnet3.stellar.org:11625 (P2P SCP)
└── friendbot.stellar.org:443 (HTTPS) — account creation
```

---

## 15. Data Flow: Request → Response (Horizon API)

```
CLIENT                         NGINX                   HORIZON                 POSTGRESQL
  │                               │                        │                       │
  │── GET /accounts/G... ──────► │                        │                       │
  │                               │── GET /... ──────────► │                       │
  │                               │                        │── SELECT accounts ──► │
  │                               │                        │── SELECT signers ────► │
  │                               │                        │◄── rows ───────────── │
  │                               │◄── JSON ───────────── │                       │
  │◄── JSON Response ─────────── │                        │                       │
```

The data served by the Horizon API comes from the PostgreSQL tables populated during ingestion.

---

## 16. Final Observations

1. **Soroban dominates the state**: Smart contracts (Soroban) represent ~58% of the total state (PERSISTENT_CONTRACT_DATA + CONTRACT_CODE + TTL). The testnet has heavy contract activity.

2. **Intentional duplication**: The two core processes download buckets separately (~9 GB total between core node + captive core). This is the cost of ingestion isolation.

3. **Large SQLite WAL**: Both SQLite databases have WALs of ~40-44 MB, indicating intensive writes during catchup. This normalizes once stable state is reached.

4. **PostgreSQL grows fast**: In ~30 minutes of catchup, the database went from 0 to ~4 GB. The `accounts_signers` table is the largest (1.4 GB with indexes) due to the multi-sig nature of Stellar.

5. **3 SDF validators**: The testnet uses 3 SDF validators with a safe quorum (fail_at=2, agreement=3). The network has 4 nodes in total.

6. **Limited P2P inbound**: Of the 225 outbound connection attempts, 221 were discarded, suggesting the core node accepts only the 3 authenticated connections from the validators.

7. **Processing rate**: ~9,7 transactions and ~15 operations per ledger on average, with peaks of up to 26 transactions and 89 operations.

---

## 17. Final Synchronization Result

Full synchronization was achieved after approximately **30-40 minutes** of container runtime.

### Final state:

| Instance | Final Ledger | State |
|----------|-------------|-------|
| Core Node | 3.663.788 | Synced! |
| Captive Core | 3.663.789 | Synced! |
| Horizon (ingest) | 3.663.788 | catch up complete |
| Horizon (history) | 3.663.788 | catch up complete |

### Synchronization process observations:

1. The Core node downloaded and applied checkpoints in batches of 64 ledgers each, starting from ledger ~3.629.312
2. During catchup, the Core node kept updating its target every ~5 applied checkpoints (e.g., from 3.663.423 to 3.663.743)
3. The Captive core consistently remained behind the Core node throughout the process (~2.000-3.000 ledgers difference)
4. Horizon remained ~6 ledgers behind the Captive core (processing/ingestion latency)
5. After reaching "Synced!" state, all components switch to real-time mode, processing new ledgers as they are closed by the Stellar testnet network (~5 seconds per ledger)
