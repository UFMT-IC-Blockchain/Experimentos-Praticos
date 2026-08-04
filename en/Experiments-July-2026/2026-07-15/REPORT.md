# Complete Report: Docker Stellar Testnet + Horizon

> **Date:** 15/07/2026 | **Container:** stellar/quickstart:testing (testnet) | **Ledger:** ~3,629,501

## Table of Contents

1. [Machine and Docker Specifications](#1-machine-and-docker-specifications)
2. [General System Architecture](#2-general-system-architecture)
3. [Initialization Process (Startup)](#3-initialization-process-startup)
4. [Container Services](#4-container-services)
5. [External Network Connections](#5-external-network-connections)
6. [Databases](#6-databases)
7. [Bucket List — State Storage](#7-bucket-list--state-storage)
8. [Complete Synchronization Flow](#8-complete-synchronization-flow)
9. [Diagrams](#9-diagrams)
10. [Conclusion](#10-conclusion)

---

## 1. Machine and Docker Specifications

### Host Machine

| Parameter | Value |
|---|---|
| **Operating System** | Microsoft Windows 11 Pro |
| **Processor** | AMD Ryzen 7 5700X3D 8-Core (16 logical processors) |
| **Total RAM** | 31.9 GB (33,437,944 KB) |
| **Free RAM** | 11.6 GB (12,154,248 KB) |
| **Docker Desktop** | v29.1.3 |
| **Docker Compose** | v5.0.0-desktop.1 |
| **WSL2 Kernel** | 6.18.33.2-microsoft-standard-WSL2 |
| **Docker Engine** | 16 CPUs, 15.56 GiB total memory |

### Docker Compose

```yaml
services:
  stellar:
    image: stellar/quickstart:testing
    container_name: stellar-testnet
    ports:
      - "8000:8000"       # Horizon API
      - "11625:11625"     # Stellar Core P2P (peer)
      - "11626:11626"     # Stellar Core HTTP (info/upgrades)
    environment:
      NETWORK: testnet
      ENABLE: core,horizon
      LOG_LEVEL: info
    volumes:
      - stellar-data:/opt/stellar
    stdin_open: true
    tty: true
    restart: unless-stopped

volumes:
  stellar-data:
```

### Container

| Parameter | Value |
|---|---|
| **Image** | `stellar/quickstart:testing` (sha256:ee95e7...) |
| **Container ID** | `4fbe5ce9b7cd` |
| **Internal IP (Docker)** | 172.18.0.2 |
| **Gateway** | 172.18.0.1 |
| **Entrypoint** | `/start` |
| **Storage Driver** | overlayfs |
| **Mounted Volumes** | `stellar-data:/opt/stellar` (~5.4 GB of data) |
| **Restart Policy** | unless-stopped |

---

## 2. General System Architecture

The `stellar/quickstart:testing` image is a "batteries included" package that packs **all** Stellar components into a single Docker image, managed by **Supervisor** (supervisord). Unlike a production-grade installation with separate containers, the quickstart runs everything in the same container to simplify development and testing.

### Installed Components

| Component | Version | Purpose |
|---|---|---|
| **Stellar Core (node)** | v27.1.0 | Participates in consensus on the testnet |
| **Stellar Core (captive)** | v27.1.0 | Only to serve data to Horizon (does not participate in consensus) |
| **Horizon** | devel (go1.26.4) | REST API for querying network data |
| **PostgreSQL** | 14 (Alpine) | Horizon's main database |
| **Nginx** | — | Reverse proxy for Horizon (port 8000) |
| **Supervisor** | — | Process manager (PID 1) |

### Container Directory Tree

```
/opt/stellar/
├── core/                    # Stellar Core Node
│   ├── bin/start            # Initialization script
│   ├── etc/
│   │   ├── stellar-core.cfg # Main configuration
│   │   └── env              # Core environment variables
│   ├── buckets/             # Bucket list (complete ledger state)
│   ├── stellar.db           # SQLite (core metadata)
│   ├── stellar-misc.db      # SQLite miscellaneous
│   └── .quickstart-initialized
├── horizon/                 # Horizon API Server
│   ├── bin/start            # Initialization script
│   ├── bin/horizon          # Horizon binary
│   ├── etc/
│   │   ├── horizon.env      # Horizon configuration
│   │   └── stellar-captive-core.cfg  # Captive core config
│   └── captive-core/
│       ├── stellar.db       # Captive core SQLite
│       ├── stellar-misc.db
│       └── captive-core/
│           ├── stellar-core.conf  # Generated captive core config
│           └── buckets/           # Captive core buckets
├── postgresql/              # PostgreSQL
│   ├── data/                # Database data
│   ├── etc/
│   │   ├── postgresql.conf  # PostgreSQL configuration
│   │   ├── pg_hba.conf      # Authentication
│   │   └── pg_ident.conf
│   └── .pgpass              # Stored password
├── nginx/                   # Nginx reverse proxy
│   ├── bin/start
│   └── etc/
│       └── nginx.conf
├── supervisor/              # Supervisord
│   └── etc/
│       └── supervisord.conf
└── stellar-rpc/             # RPC Server (not enabled in our setup)
```

---

## 3. Initialization Process

The `/start` entrypoint (a bash script of ~600 lines) orchestrates the entire initialization. The flow is:

### Phase 1: Network Configuration (process_args)

Based on the `NETWORK=testnet` variable, the script defines:

```bash
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
```

It calculates the `NETWORK_ID` (sha256 hash of the passphrase) and derives the keys of the network's root account.

### Phase 2: Copy Defaults (copy_defaults)

Copies the default configuration files from `/opt/stellar-default/{common,testnet}/` to each service's directories. This only happens on the **first run** (empty directories). On subsequent runs, the directories already exist (persisted in the volume) and the copy is skipped.

### Phase 3: Database Initialization (init_db)

- Generates a random password for PostgreSQL (displayed in the log)
- Runs `initdb` on PostgreSQL
- Creates the databases: `horizon` (and `core` if `CORE_USE_POSTGRES=true`)
- Creates the `stellar` user with privileges
- Stops PostgreSQL (it will be restarted by Supervisor later)

### Phase 4: Stellar Core Initialization (init_stellar_core)

- Replaces placeholders in `stellar-core.cfg`:
  - `__NETWORK__` → `"Test SDF Network ; September 2015"`
  - `__MANUAL_CLOSE__` → `false`
  - `__DATABASE__` → `sqlite3:///opt/stellar/core/stellar.db`
- Runs `stellar-core new-db` to create the SQLite schema
- Creates the `.quickstart-initialized` file to avoid repetition

### Phase 5: Horizon Initialization (init_horizon)

- Replaces placeholders in `horizon.env` and `stellar-captive-core.cfg`
- Runs `horizon db init` to create the 33 tables in PostgreSQL
- Creates the `.quickstart-initialized` file

### Phase 6: Supervisor Initialization (exec_supervisor)

Supervisor manages the child processes with these priorities:

| Priority | Service | Autostart | Description |
|---|---|---|---|
| 10 | postgresql | false | Database |
| 20 | stellar-core | false | Consensus node |
| 30 | horizon | false | API server |
| 50 | nginx | **true** | Reverse proxy |

Services marked as `autostart=false` are started manually by the `start_optional_services()` script after Supervisor is running.

### Phase 7: Local Upgrade and Monitoring

- `upgrade_local()`: Only for the `local` network (config upgrades)
- `service_status()`: Loops that monitor the status of each stellar-core and horizon, displaying in the log
- `start_optional_services()`: Starts postgresql → stellar-core → horizon (in this order)

---

## 4. Container Services

### 4.1 Supervisor

- **PID:** 1
- **Command:** `/usr/bin/python3 /bin/supervisord -n -c /opt/stellar/supervisor/etc/supervisord.conf`
- **Port:** 9001 (localhost, HTTP interface)
- **Role:** Process manager. Keeps all services running, restarts them if necessary.
- **Config:** Reads files from `/opt/stellar/supervisor/etc/supervisord.conf.d/`

### 4.2 Stellar Core — Consensus Node (Node)

- **PID:** 291
- **User:** stellar
- **Command:** `/usr/bin/stellar-core --conf /opt/stellar/core/etc/stellar-core.cfg run`
- **Memory Usage:** ~2.8 GB (17.6% of the container total)
- **CPU:** ~12% (can reach 100% during catchup)
- **Ports:**
  - `11625` (P2P — listens on 0.0.0.0) — communication with peers
  - `11626` (HTTP — listens on 0.0.0.0) — info/upgrades API

#### Complete Configuration

```ini
HTTP_PORT=11626
PUBLIC_HTTP_PORT=true
LOG_FILE_PATH="/var/log/stellar-core/stellar-core-{datetime:%Y-%m-%d_%H-%M-%S}.log"
MANUAL_CLOSE=false

NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/core/stellar.db"
CATCHUP_RECENT=100
UNSAFE_QUORUM=true
FAILURE_SAFETY=1

[[HOME_DOMAINS]]
HOME_DOMAIN="testnet.stellar.org"
QUALITY="HIGH"

[[VALIDATORS]]
NAME="sdf_testnet_1"
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y"
ADDRESS="core-testnet1.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_001/{0} -o {1}"

[[VALIDATORS]]
NAME="sdf_testnet_2"
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GCUCJTIYXSOXKBSNFGNFWW5MUQ54HKRPGJUTQFJ5RQXZXNOLNXYDHRAP"
ADDRESS="core-testnet2.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_002/{0} -o {1}"

[[VALIDATORS]]
NAME="sdf_testnet_3"
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GC2V2EFSXN6SQTWVYA5EPJPBWWIMSD2XQNKUOHGEKB535AQE2I6IXV2Z"
ADDRESS="core-testnet3.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_003/{0} -o {1}"
```

**Important parameters:**

| Parameter | Value | Meaning |
|---|---|---|
| `CATCHUP_RECENT` | 100 | How many recent ledgers to fetch via history archive |
| `UNSAFE_QUORUM` | true | Accepts quorum even without trusted nodes configured (safe for testnet) |
| `FAILURE_SAFETY` | 1 | Failure tolerance (f = 1, requires 3 validators) |
| `MANUAL_CLOSE` | false | Automatic ledger closing (not manual) |
| `DATABASE` | sqlite3://... | Local database, does not use PostgreSQL |

**Role:** Actively participates in the SCP (Stellar Consensus Protocol), maintains P2P connections with testnet peers, validates transactions, and updates its local ledger. It is the network's "full node".

### 4.3 Stellar Core — Captive Core (Horizon)

- **PID:** 3985
- **User:** stellar
- **Command:** `/usr/bin/stellar-core --conf /opt/stellar/horizon/captive-core/captive-core/stellar-core.conf --console run --metadata-output-stream fd:3`
- **Memory Usage:** ~2.9 GB (17.9%)
- **CPU:** ~4.5%
- **Ports:**
  - `11725` (P2P — listens on 0.0.0.0)
  - `11726` (HTTP — listens on localhost:11726)

#### Crucial Differences between Node and Captive Core

| Characteristic | Node (PID 291) | Captive Core (PID 3985) |
|---|---|---|
| **Participates in consensus?** | Yes | **No** |
| **Connects to peers?** | Yes (P2P) | Yes (only for initial catchup) |
| **Database** | SQLite (`stellar.db`) | SQLite (`captive-core/stellar.db`) |
| **Bucket list** | Shared | Isolated (own) |
| **HTTP port** | 11626 (public) | 11726 (localhost only) |
| **P2P port** | 11625 (public) | 11725 (public) |
| **Started by?** | Supervisor → `core/bin/start` | Horizon (as a subprocess) |
| **Lifecycle** | Permanent | Ephemeral (starts/stops with ingestion) |
| **Execution mode** | `run` (normal) | `--console run --metadata-output-stream fd:3` (metadata streaming) |
| **Bucket DB** | Uses default index page size | `BUCKETLIST_DB_INDEX_PAGE_SIZE_EXPONENT=12`, `BUCKETLIST_DB_MEMORY_FOR_CACHING=0` |
| **Backfill restore** | No | `BACKFILL_RESTORE_META=true` |

**Role:** Captive Core is a **disposable** stellar-core that Horizon starts as a subprocess ONLY to perform data ingestion. It does not participate in consensus, does not accept peer connections (it only performs the initial catchup from archives), and is discarded/recreated as needed. Horizon reads the metadata stream output (`fd:3`) to process transactions and feed PostgreSQL.

### 4.4 Horizon API Server

- **PID:** 349
- **User:** stellar
- **Command:** `/usr/bin/stellar-horizon`
- **Memory Usage:** ~182 MB (1.1%)
- **CPU:** ~8.8%
- **Port:** 8001 (internal), exposed as 8000 via Nginx

#### Configuration (horizon.env)

```bash
export DATABASE_URL="postgres://stellar:s9YVDakFZwTcrb7h@localhost/horizon"
export STELLAR_CORE_URL="http://localhost:11726"
export STELLAR_CORE_BINARY_PATH=/usr/bin/stellar-core
export LOG_LEVEL="info"
export ENABLE_CAPTIVE_CORE_INGESTION="true"
export CAPTIVE_CORE_USE_DB=true
export INGEST="true"
export PER_HOUR_RATE_LIMIT="72000"
export NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
export HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
export ADMIN_PORT=6060
export PORT=8001
export CHECKPOINT_FREQUENCY=64
export INGEST_DISABLE_STATE_VERIFICATION=True
export CAPTIVE_CORE_CONFIG_PATH=/opt/stellar/horizon/etc/stellar-captive-core.cfg
export CAPTIVE_CORE_STORAGE_PATH=/opt/stellar/horizon/captive-core
export STELLAR_CORE_VERSION="v27.1.0"
```

**Role:** Horizon is the REST API server that allows querying balances, transactions, operations, effects, etc. It performs data **ingestion**: it reads the ledger from Captive Core, processes and stores it in PostgreSQL in a structured way (history + current state).

### 4.5 PostgreSQL

- **PID:** 330
- **User:** postgres
- **Version:** 14 (Alpine)
- **Memory Usage:** ~25 MB (0.1% — only the main process; the workers add up more)
- **Port:** 5432

#### Relevant Configuration

| Parameter | Value |
|---|---|
| `max_connections` | 150 |
| `shared_buffers` | 128 MB |
| `listen_addresses` | `*` |
| `ssl` | true (snakeoil certificate) |
| `data_directory` | `/opt/stellar/postgresql/data` |

#### Authentication (pg_hba.conf)

```
local   all   postgres   peer
local   all   all        md5
host    all   all        127.0.0.1/32    md5
host    all   all        0.0.0.0/0       md5
host    all   all        ::1/128         md5
```

### 4.6 Nginx

- **PID:** 288 (master), 289 (worker)
- **User:** www-data
- **Port:** 8000 (external)
- **Role:** Reverse proxy. Forwards requests from port 8000 to Horizon (port 8001). It also includes `conf.d/` files for other services (RPC, Friendbot, Lab).

---

## 5. External Network Connections

### Active Connections (ESTABLISHED)

stellar-core maintains persistent P2P connections with testnet peers. During our run, we captured:

| Peer IP | Port | Status |
|---|---|---|
| 13.223.55.158 | 11625 | ESTAB |
| 44.204.146.210 | 11625 | ESTAB |
| 3.85.105.105 | 11625 | ESTAB |
| 44.206.255.84 | 11625 | ESTAB |
| 44.213.67.110 | 11625 | ESTAB |
| 98.91.174.101 | 11625 | ESTAB (2 connections) |
| 141.98.219.89 | 11625 | ESTAB |
| 54.159.155.163 | 11625 | ESTAB |
| 18.220.162.149 | **11725** | ESTAB (captive core) |

### Connections in Progress (SYN-SENT)

| Peer IP | Port |
|---|---|
| 107.21.193.235 | 30020 |
| 89.124.115.249 | 11625 |
| 200.129.247.55 | 11625 |
| 18.212.206.26 | 30020 |

### History Archive Endpoints

stellar-core downloads the historical state from these URLs:

| URL | Description |
|---|---|
| `http://history.stellar.org/prd/core-testnet/core_testnet_001/{0}` | Archive 1 (SDF) |
| `http://history.stellar.org/prd/core-testnet/core_testnet_002/{0}` | Archive 2 (SDF) |
| `http://history.stellar.org/prd/core-testnet/core_testnet_003/{0}` | Archive 3 (SDF) |

### Testnet Validators (SDF)

| Name | Public Key | Address |
|---|---|---|
| sdf_testnet_1 | `GDKXE2OZMJI...` | core-testnet1.stellar.org |
| sdf_testnet_2 | `GCUCJTIYXSOX...` | core-testnet2.stellar.org |
| sdf_testnet_3 | `GC2V2EFSXN6...` | core-testnet3.stellar.org |

---

## 6. Databases

### 6.1 PostgreSQL (Horizon)

**Database:** `horizon`
**User:** `stellar`
**Total size:** ~1.2 GB

#### 33 Tables (with sizes)

| Table | Size | Purpose |
|---|---|---|
| `accounts` | **497 MB** | Accounts with balances and sequences |
| `accounts_signers` | **428 MB** | Signers of each account |
| `accounts_data` | **94 MB** | Data entries of the accounts |
| `trust_lines` | **107 MB** | Trust lines (balance of non-native assets) |
| `offers` | **12 MB** | Open offers |
| `exp_asset_stats` | **23 MB** | Asset statistics |
| `history_transactions` | **10 MB** | Historical transactions |
| `history_operations` | **3.3 MB** | Historical operations |
| `claimable_balances` | **5 MB** | Claimable balances |
| `contract_asset_balances` | **6 MB** | Soroban contract balances |
| `history_ledgers` | **320 kB** | Ledger metadata |
| `history_effects` | **536 kB** | Operation effects |
| `history_operation_participants` | **384 kB** | Operation participants |
| `history_transaction_participants` | **312 kB** | Transaction participants |
| `history_assets` | **8 kB** | Historical assets |
| `liquidity_pools` | **872 kB** | Liquidity pools |
| `gorp_migrations` | **16 kB** | Migration control |
| `key_value_store` | **56 kB** | Auxiliary KV store |
| `asset_contracts`, `account_filter_rules`, `asset_filter_rules` | — | Filter/gas rules |
| `history_claimable_balances` | 16 kB | Historical claimable balances |
| `history_liquidity_pools` | 8 kB | Historical liquidity pools |
| `history_trades`, `history_trades_60000` | — | Historical trades |
| `contract_asset_stats` | 192 kB | Contract stats |
| `history_operation_*`, `history_transaction_*` | — | Join tables |

### 6.2 SQLite (Stellar Core Node)

**File:** `/opt/stellar/core/stellar.db`
**Size:** ~18 MB (with WAL: ~62 MB)

Stores stellar-core metadata: ledger headers, consensus accounts, quorum sets, etc.

**File:** `/opt/stellar/core/stellar-misc.db` (~22 MB with WAL)

Stores miscellaneous data (known peers, bans, etc.)

### 6.3 SQLite (Captive Core - Horizon)

**File:** `/opt/stellar/horizon/captive-core/stellar.db`
**Size:** ~21 MB (with WAL: ~33 MB)

**File:** `/opt/stellar/horizon/captive-core/stellar-misc.db` (~14 MB with WAL)

---

## 7. Bucket List — State Storage

### What is the Bucket List?

The **Bucket List** is Stellar Core's state storage mechanism. Unlike a traditional database, it is an **immutable, merge-based** data structure that stores the complete ledger state (accounts, balances, offers, trust lines, etc.) in XDR files called "buckets".

### Characteristics

- **Immutable:** Buckets are never modified after creation. Changes generate NEW buckets.
- **Levels:** The bucket list has 11 levels (0-10). Each level contains buckets that represent state snapshots at different time scales.
- **Merge:** Periodically, buckets from lower levels are merged into higher levels (compaction).
- **Hashes:** Each bucket is identified by a SHA-256 hash of its content.
- **Format:** `.xdr` files (XDR serialization) with `.index` files for lookup.

### Directory Structure

**Node Core** (`/opt/stellar/core/buckets/`):
```
buckets/
├── bucket-<hash>.xdr       # Bucket data (XDR)
├── bucket-<hash>.index     # Bucket index
├── history/                # Historical data (ledger, transactions, results)
├── meta-debug/             # Debug metadata
│   ├── debug-tx-set.xdr
│   └── meta-debug-<ledger>-<hash>.xdr.gz
├── publishqueue/           # Publish queue
└── tmp/                    # Temporary files during merge
```

**Total size:** ~4.7 GB (node) + ~5.4 GB (captive core) = ~10 GB

### Largest Buckets

| Bucket (Node) | Size |
|---|---|
| `bucket-ff26b4f5...xdr` | **822 MB** |
| `bucket-eb7625ce...xdr` | **639 MB** |
| `bucket-d8522ede...xdr` | **629 MB** |
| `bucket-b2a2c09a...xdr` | **371 MB** |
| `bucket-8a27deda...xdr` | **473 MB** |

### How the Bucket List Connects to the System

```mermaid
flowchart LR
    subgraph "External"
        HA[History Archives<br/>https://history.stellar.org]
        P2P[Peers P2P<br/>core-testnet1/2/3]
    end

    subgraph "Stellar Core Node"
        BC[Bucket List<br/>4.7 GB]
        SQL1[(SQLite<br/>stellar.db)]
    end

    subgraph "Captive Core (Horizon)"
        BC2[Bucket List<br/>5.4 GB<br/>captive-core/buckets/]
        SQL2[(SQLite<br/>captive-core/stellar.db)]
    end

    subgraph "Horizon"
        H[Horizon API]
        PG[(PostgreSQL<br/>33 tables)]
    end

    P2P -->|SCP Consensus| BC
    HA -->|Initial download| BC
    BC -->|Snapshot state| SQL1

    HA -->|Catchup| BC2
    BC2 -->|Metadata stream| H
    H -->|Ingestion| PG
    
    H -->|Query| PG
    User -->|HTTP :8000| H
```

### Catchup Process

1. **Determine trigger ledger:** The core queries peers to find out the most recent ledger
2. **Download state files:** Downloads history JSON files that describe which snapshot to download
3. **Download buckets:** Downloads buckets from the history archive (dozens of files, up to 800 MB each)
4. **Verification:** Verifies the SHA-256 hash of each bucket
5. **Apply:** Applies the buckets to the local bucket list
6. **Download checkpoints:** Downloads incremental ledgers (checkpoints) up to the current state
7. **Apply buffered ledgers:** Applies buffered ledgers until reaching the most recent state
8. **Synced!** — The node is synchronized and starts participating in consensus

---

## 8. Complete Synchronization Flow

### Real Timeline (from our container)

| Time | Event | Ledger |
|---|---|---|
| 00:57:23 | Container starts | — |
| 00:57:30 | PostgreSQL available | — |
| 00:57:33 | stellar-core node starts | — |
| 00:57:35 | Horizon starts (ingestion mode) | — |
| 00:57:35 | **Catching up** — ETA: 280s | 3,629,377 |
| 00:57:35 | Download of state files + buckets | 3,629,311 |
| 00:59:xx | Bucket download: 8% → 70% | — |
| 01:04:xx | Download complete → Applying buckets | — |
| 01:05:xx | **Succeeded: download-verify-apply-buckets** | 3,629,309 |
| 01:05:xx | Download remaining checkpoints | — |
| 01:05:xx | Captive Core **Connected** | 3,629,376 |
| 01:08:xx | Node **Synced!** | 3,629,436 |
| 01:09:xx | Horizon core: downloading ledger files | 3,629,375 |
| 01:11:23 | **Horizon: ingestion caught up** | 3,629,501 |
| 01:11:48 | Core latest ledger | 3,629,501 |

**Total time to synchronize:** ~14 minutes (first run, with hot buckets in cache)

---

## 9. Diagrams

### 9.1 Databases — ER Diagram

![ER Diagram of Databases](../Docker-Stellar/diagrams/png/01-databases.png)

Entity-relationship diagram of the databases: PostgreSQL (Horizon), SQLite (Node and Captive Core) and Bucket Lists, with sizes and main tables.

```mermaid
erDiagram
    POSTGRESQL_HORIZON ||--o{ ACCOUNTS : "1.2 GB total"
    POSTGRESQL_HORIZON ||--o{ ACCOUNTS_SIGNERS : ""
    POSTGRESQL_HORIZON ||--o{ TRUST_LINES : ""
    POSTGRESQL_HORIZON ||--o{ OFFERS : ""
    POSTGRESQL_HORIZON ||--o{ HISTORY_TRANSACTIONS : ""
    POSTGRESQL_HORIZON ||--o{ HISTORY_OPERATIONS : ""
    POSTGRESQL_HORIZON ||--o{ HISTORY_LEDGERS : ""
    POSTGRESQL_HORIZON ||--o{ CLAIMABLE_BALANCES : ""
    POSTGRESQL_HORIZON ||--o{ CONTRACT_ASSET_BALANCES : ""
    POSTGRESQL_HORIZON ||--o{ LIQUIDITY_POOLS : ""

    SQLITE_CORE_NODE ||--o{ STELLAR_DB : "stellar.db ~18MB"
    SQLITE_CORE_NODE ||--o{ STELLAR_MISC_DB : "stellar-misc.db"

    SQLITE_CAPTIVE_CORE ||--o{ CAPTIVE_STELLAR_DB : "captive-core/stellar.db ~21MB"
    SQLITE_CAPTIVE_CORE ||--o{ CAPTIVE_MISC_DB : "captive-core/stellar-misc.db"

    BUCKET_LIST_NODE ||--o{ BUCKETS_NODE : "~4.7 GB in .xdr files"
    BUCKET_LIST_CAPTIVE ||--o{ BUCKETS_CAPTIVE : "~5.4 GB in .xdr files"

    POSTGRESQL_HORIZON {
        string database "horizon"
        string user     "stellar"
        int    tables   "33 tables"
        string engine   "PostgreSQL 14"
    }

    ACCOUNTS {
        string table     "accounts"
        string size      "497 MB"
        string desc      "Accounts with balances and sequences"
    }

    ACCOUNTS_SIGNERS {
        string table     "accounts_signers"
        string size      "428 MB"
        string desc      "Signers of each account"
    }

    TRUST_LINES {
        string table     "trust_lines"
        string size      "107 MB"
        string desc      "Trust lines of non-native assets"
    }

    OFFERS {
        string table     "offers"
        string size      "12 MB"
        string desc      "Open offers"
    }

    HISTORY_TRANSACTIONS {
        string table     "history_transactions"
        string size      "10 MB"
        string desc      "Historical transactions"
    }

    SQLITE_CORE_NODE {
        string engine "SQLite"
        string path   "/opt/stellar/core/"
        string desc   "Stellar Core Node metadata"
    }

    SQLITE_CAPTIVE_CORE {
        string engine "SQLite"
        string path   "/opt/stellar/horizon/captive-core/"
        string desc   "Captive Core metadata"
    }

    BUCKET_LIST_NODE {
        string format ".xdr + .index files"
        string path   "/opt/stellar/core/buckets/"
        string levels "11 levels (0-10)"
    }

    BUCKET_LIST_CAPTIVE {
        string format ".xdr + .index files"
        string path   "/opt/stellar/horizon/captive-core/captive-core/buckets/"
        string levels "11 levels (0-10)"
    }
```

### 9.2 Horizon Tables — Mindmap

![Tables Mindmap](../Docker-Stellar/diagrams/png/02-tables.png)

Mindmap of the 33 PostgreSQL tables organized by category: Current State, History, Auxiliary and Join.

```mermaid
mindmap
  root((Horizon Tables<br/>33 tables))
    Current_State
      accounts[accounts<br/>497 MB]
      accounts_signers[accounts_signers<br/>428 MB]
      accounts_data[accounts_data<br/>94 MB]
      trust_lines[trust_lines<br/>107 MB]
      offers[offers<br/>12 MB]
      claimable_balances[claimable_balances<br/>5 MB]
      liquidity_pools[liquidity_pools<br/>872 KB]
      contract_asset_balances[contract_asset_balances<br/>6 MB]
      contract_asset_stats[contract_asset_stats<br/>192 KB]
      asset_contracts[asset_contracts<br/>112 KB]
    History
      history_ledgers[history_ledgers<br/>320 KB]
      history_transactions[history_transactions<br/>10 MB]
      history_operations[history_operations<br/>3.3 MB]
      history_effects[history_effects<br/>536 KB]
      history_accounts[history_accounts<br/>88 KB]
      history_assets[history_assets<br/>8 KB]
      history_operation_participants[history_operation_participants<br/>384 KB]
      history_transaction_participants[history_transaction_participants<br/>312 KB]
      history_claimable_balances[history_claimable_balances<br/>16 KB]
      history_liquidity_pools[history_liquidity_pools<br/>8 KB]
      history_trades[history_trades<br/>8 KB]
    Auxiliary
      exp_asset_stats[exp_asset_stats<br/>23 MB]
      key_value_store[key_value_store<br/>56 KB]
      account_filter_rules[account_filter_rules<br/>16 KB]
      asset_filter_rules[asset_filter_rules<br/>16 KB]
      gorp_migrations[gorp_migrations<br/>16 KB]
      history_transactions_filtered_tmp[history_transactions_filtered_tmp<br/>8 KB]
    Join_Tables
      history_operation_claimable_balances
      history_operation_liquidity_pools
      history_transaction_claimable_balances
      history_transaction_liquidity_pools
      history_trades_60000
```

### 9.3 Container Services

![Services Diagram](../Docker-Stellar/diagrams/png/03-services.png)

Service architecture inside the container: Supervisor managing PostgreSQL, Stellar Core Node, Horizon and Nginx, with Captive Core as a subprocess of Horizon.

```mermaid
graph TB
    subgraph Container["Container: stellar-testnet (172.18.0.2)"]
        subgraph Managed["Managed by Supervisor"]
            direction TB
            PG[("PostgreSQL 14<br/>:5432<br/>PID 330<br/>~25 MB RAM")]
            CN["Stellar Core Node<br/>PID 291<br/>~2.8 GB RAM<br/>:11625 P2P<br/>:11626 HTTP"]
            HZ["Horizon API<br/>PID 349<br/>~182 MB RAM<br/>:8001 HTTP"]
            NX["Nginx<br/>PID 288<br/>:8000 HTTP"]
        end
        
        CC["Captive Core<br/>PID 3985<br/>~2.9 GB RAM<br/>:11725 P2P<br/>:11726 HTTP<br/>Subprocess of Horizon"]
    end

    SUP["Supervisord<br/>PID 1"] -.->|start_optional_services| PG
    SUP -.->|start_optional_services| CN
    SUP -.->|start_optional_services| HZ
    SUP -->|autostart=true| NX
    
    HZ -->|subprocess| CC
    HZ -->|"SQL query<br/>DATABASE_URL"| PG
    HZ -->|"HTTP query<br/>STELLAR_CORE_URL"| CC
    
    NX -->|"reverse proxy<br/>:8000 -> :8001"| HZ
    
    CN -->|"STELLAR_CORE_URL<br/>http://localhost:11726"| HZ
    
    style Container fill:#1a1a2e,color:#fff,stroke:#e94560
    style Managed fill:#16213e,color:#fff,stroke:#0f3460
    style PG fill:#2d6a4f,color:#fff
    style CN fill:#e07a5f,color:#fff
    style CC fill:#e07a5f,color:#fff,stroke:#81b29a
    style HZ fill:#3d5a80,color:#fff
    style NX fill:#6c5b7b,color:#fff
    style SUP fill:#f2cc8f,color:#000
```

### 9.4 Synchronization Flow (Sequence)

![Synchronization Diagram](../Docker-Stellar/diagrams/png/04-synchronization.png)

Complete synchronization flow in 5 phases: Discovery, State Download, Checkpoints, Horizon Ingestion and Continuous Operation.

```mermaid
sequenceDiagram
    participant HA as History Archives<br/>history.stellar.org
    participant P2P as Peers Testnet
    participant CN as Stellar Core Node<br/>PID 291
    participant CC as Captive Core<br/>PID 3985
    participant HZ as Horizon<br/>PID 349
    participant PG as PostgreSQL<br/>horizon DB

    rect rgb(20, 30, 50)
        Note over CN,HZ: PHASE 1: DISCOVERY
        P2P->>CN: Connect to peers (port 11625)
        P2P-->>CN: Ledger info: SCR = 3,629,377
        CN->>HA: Fetch latest checkpoint
    end

    rect rgb(30, 50, 30)
        Note over CN,HZ: PHASE 2: STATE DOWNLOAD
        CN->>HA: Download state file (history-*.json)
        CN->>HA: Download buckets (36-37 .xdr files)
        CN->>CN: Verify SHA-256 hashes
        CN->>CN: Apply buckets (0% -> 100%)
        Note over CN: Succeeded: download-verify-apply-buckets
    end

    rect rgb(50, 30, 30)
        Note over CN,HZ: PHASE 3: CHECKPOINTS
        CN->>HA: Download checkpoint ledgers
        CN->>CN: Apply checkpoints (2 left -> 0)
        CN->>CN: Apply buffered ledgers
        CN->>CN: Synced!
        Note over CN: Node Synced!<br/>Participating in SCP consensus
    end

    rect rgb(20, 50, 50)
        Note over CN,HZ: PHASE 4: HORIZON INGESTION
        HZ->>HZ: Start captive core subprocess
        HZ->>CC: stellar-core --console run --metadata-output-stream fd:3
        CC->>HA: Buckets download (.xdr files)
        CC->>HA: Checkpoints download
        CC->>HA: Ledger files download
        loop Every 64 ledgers (checkpoint)
            CC->>HZ: Metadata stream (fd:3)
            HZ->>HZ: Process transactions & operations
            HZ->>PG: INSERT into history_transactions
            HZ->>PG: INSERT into history_operations
            HZ->>PG: INSERT into history_effects
            HZ->>PG: UPDATE accounts, offers, trust_lines
        end
        Note over HZ: Horizon: ingestion caught up
    end

    rect rgb(50, 50, 20)
        Note over CN,HZ: PHASE 5: CONTINUOUS OPERATION
        P2P->>CN: New ledgers (SCP consensus)
        CN->>CC: HTTP /info (latest ledger)
        CC->>HZ: Metadata stream (new transactions)
        HZ->>PG: Real-time updates
        User->>HZ: GET http://localhost:8000/accounts/:id
        HZ->>PG: SELECT * FROM accounts WHERE ...
        PG-->>HZ: Account data
        HZ-->>User: JSON response
    end
```

### 9.5 Bucket List Hierarchy

![Bucket List Diagram](../Docker-Stellar/diagrams/png/05-bucket-list.png)

Hierarchy of the 11 Bucket List levels (0-10) with sizes, merge process and connection to History Archives.

```mermaid
graph TB
    subgraph BUCKET_LIST["Bucket List (11 levels: 0 to 10)"]
        L0["Level 0<br/>~25 KB<br/>2-4 buckets<br/>Recent ledgers"]
        L1["Level 1<br/>~47 KB<br/>2-4 buckets"]
        L2["Level 2<br/>~1.6 MB<br/>2-4 buckets"]
        L3["Level 3<br/>~1.1 MB<br/>2-4 buckets"]
        L4["Level 4<br/>~1.8 MB<br/>2-4 buckets"]
        L5["Level 5<br/>~6.5 MB<br/>2 buckets"]
        L6["Level 6<br/>~40 MB<br/>2 buckets"]
        L7["Level 7<br/>~103 MB<br/>2 buckets"]
        L8["Level 8<br/>~211 MB<br/>2 buckets"]
        L9["Level 9<br/>~629 MB<br/>2 buckets"]
        L10["Level 10<br/>~822 MB<br/>2 buckets<br/>Complete snapshot"]
    end

    subgraph FILES["Files per Bucket"]
        XDR["bucket-{sha256}.xdr<br/>XDR serialized data"]
        INDEX["bucket-{sha256}.index<br/>Index for lookup<br/>binary search"]
    end

    LEDGER["NEW LEDGER<br/>state updates"] -->|"enters as<br/>level 0 bucket"| L0
    L0 -->|"periodic merge<br/>every 64 ledgers"| L1
    L1 -->|merge| L2
    L2 -->|merge| L3
    L3 -->|merge| L4
    L4 -->|merge| L5
    L5 -->|merge| L6
    L6 -->|merge| L7
    L7 -->|merge| L8
    L8 -->|merge| L9
    L9 -->|merge| L10

    L0 -.->|"contains .xdr + .index"| FILES
    L1 -.-> FILES

    HISTORY["History Archives<br/>history.stellar.org"] -->|"download<br/>initial catchup"| L10
    L10 -->|"upload<br/>new snapshot"| HISTORY
```

### 9.6 External Network Connections

![Network Connections Diagram](../Docker-Stellar/diagrams/png/06-connections.png)

Container network connections with SDF validators, P2P peers, History Archives and the local user.

```mermaid
graph LR
    subgraph INTERNET["Internet"]
        V1["core-testnet1.stellar.org<br/>SDF Validator 1"]
        V2["core-testnet2.stellar.org<br/>SDF Validator 2"]
        V3["core-testnet3.stellar.org<br/>SDF Validator 3"]
        HA1["history.stellar.org<br/>prd/core-testnet/<br/>core_testnet_001"]
        HA2["history.stellar.org<br/>prd/core-testnet/<br/>core_testnet_002"]
        HA3["history.stellar.org<br/>prd/core-testnet/<br/>core_testnet_003"]
        PEERS["Random peers<br/>~10 P2P connections<br/>13.223.55.158<br/>44.204.146.210<br/>3.85.105.105<br/>44.206.255.84<br/>44.213.67.110<br/>98.91.174.101<br/>141.98.219.89<br/>54.159.155.163"]
    end

    subgraph DOCKER["Docker Network"]
        CT["Container<br/>stellar-testnet<br/>172.18.0.2"]
    end

    subgraph HOST["Host Windows"]
        USER["User<br/>localhost:8000"]
    end

    V1 -->|":11625 P2P"| CT
    V2 -->|":11625 P2P"| CT
    V3 -->|":11625 P2P"| CT
    PEERS -->|":11625 P2P"| CT
    PEERS -->|":11725 P2P<br/>Captive Core"| CT
    
    CT -->|"HISTORY curl<br/>state + buckets"| HA1
    CT -->|"HISTORY curl"| HA2
    CT -->|"HISTORY curl"| HA3

    USER -->|"HTTP :8000<br/>Horizon API"| CT
```

### 9.7 General Services Architecture (Simplified View)

```mermaid
graph TB
    subgraph "Container: stellar-testnet"
        S[Supervisord<br/>PID 1]
        
        subgraph "Managed by Supervisor"
            direction LR
            PG[("PostgreSQL<br/>:5432")]
            CN[Stellar Core Node<br/>PID 291<br/>:11625 :11626]
            HZ[Horizon API<br/>PID 349<br/>:8001]
            NX[Nginx<br/>PID 288<br/>:8000]
        end
        
        CC[Captive Core<br/>PID 3985<br/>Not managed<br/>:11725 :11726]
    end
    
    S -->|start_optional_services| PG
    S -->|start_optional_services| CN
    S -->|start_optional_services| HZ
    S -->|autostart=true| NX
    
    HZ -->|subprocess| CC
    HZ -->|query| PG
    HZ -->|query| CC
    
    NX -->|reverse proxy :8000| HZ
    
    CN -->|reports status| HZ
```

### 9.8 Initialization Flow (Startup)

```mermaid
flowchart TD
    A["/start<br/>Entrypoint"] --> B[process_args<br/>Defines NETWORK, vars]
    B --> C[copy_defaults<br/>Copies configs to /opt/stellar/]
    C --> D{First<br/>run?}
    D -->|Yes| E[init_db<br/>PostgreSQL initdb + creation]
    D -->|No| F[Skips initialization]
    E --> F
    F --> G[init_stellar_core<br/>new-db + configuration]
    G --> H[init_horizon<br/>db init + 33 tables]
    H --> I[stop_postgres<br/>Stops PG temporarily]
    I --> J[exec_supervisor<br/>Starts supervisord]
    J --> K[start_optional_services]
    K --> L[Supervisor starts<br/>postgresql]
    L --> M[Supervisor starts<br/>stellar-core node]
    M --> N[stellar-core performs<br/>catchup + sync]
    N --> O[Supervisor starts<br/>horizon]
    O --> P[Horizon starts<br/>captive core]
    P --> Q[Captive core performs<br/>catchup + sync]
    Q --> R[Horizon: ingestion<br/>caught up ✅]
    R --> S[System ready<br/>:8000 responding]
    
    style R fill:#4caf50,color:white
    style S fill:#2196f3,color:white
```

---

## 10. Conclusion

### Storage Data Summary

| Component | Technology | Size | Location |
|---|---|---|---|
| Bucket List (Node) | .xdr files | **4.7 GB** | `/opt/stellar/core/buckets/` |
| Bucket List (Captive) | .xdr files | **5.4 GB** | `/opt/stellar/horizon/captive-core/captive-core/buckets/` |
| SQLite (Node) | SQLite | **62 MB** (with WAL) | `/opt/stellar/core/stellar.db` |
| SQLite (Captive) | SQLite | **33 MB** (with WAL) | `/opt/stellar/horizon/captive-core/stellar.db` |
| PostgreSQL (Horizon) | PostgreSQL | **~1.2 GB** | Docker Volume (`/opt/stellar/postgresql/data/`) |
| **Total** | | **~10-11 GB** | Docker Volume `stellar-data` |

### Why 2 Stellar Core Instances?

The use of **two instances** of stellar-core (node + captive) is a deliberate architecture of modern Horizon:

1. **Node (PID 291):** Maintains the complete network state, participates in SCP consensus, connects to peers. It is the "verifier" that ensures the data is correct.

2. **Captive Core (PID 3985):** It is a **disposable** and **isolated** instance that Horizon manages. It does not participate in consensus — it only performs catchup via history archives and sends transaction metadata to Horizon via pipe (`fd:3`). This allows Horizon to perform ingestion without interfering with the main node.

### How Does Horizon Know What Is Happening?

Horizon connects to Captive Core via:

1. **HTTP** (`STELLAR_CORE_URL=http://localhost:11726`) — to get current ledger information
2. **Metadata Stream** (`--metadata-output-stream fd:3`) — pipe to receive real-time transaction metadata
3. **SQLite Database** (`CAPTIVE_CORE_USE_DB=true`) — direct access to the captive core database

### Useful Commands

```bash
# View stellar-core node logs
docker compose logs stellar-testnet | grep "stellar-core(node)"

# View captive core logs
docker compose logs stellar-testnet | grep "stellar-core(horizon)"

# View horizon logs
docker compose logs stellar-testnet | grep "horizon:"

# Check current status via API
curl -s http://localhost:8000 | jq '.core_latest_ledger, .history_latest_ledger'

# List connected peers
curl -s http://localhost:11626/peers | jq '.outgoing_peers[] | {ip, port, lat}'

# View stellar-core node info
curl -s http://localhost:11626/info | jq '.info.state, .info.ledger.num, .info.peers'
```

---

> **Report generated on:** 15/07/2026  
> **Based on the container:** stellar/quickstart:testing (testnet)  
> **Ledger at collection time:** ~3,629,501