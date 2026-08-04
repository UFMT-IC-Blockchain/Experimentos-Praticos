# Docker Stellar Core + Horizon — MainNet

**Purpose:** Study of data storage optimization techniques in blockchain environments
**Network:** Stellar MainNet ("Public Global Stellar Network ; September 2015")
**Architecture:** 2 separate containers (stellar-core + stellar-horizon)
**Based on:** `Docker-Core-Horizon-Separated` (TestNet), configured for MainNet

---

## 1. Study Context

This setup was created to investigate **how data is stored, replicated, and processed** in a full node of the Stellar network (MainNet). Unlike blockchains such as Bitcoin (UTXO) or Ethereum (state trie), Stellar uses a **bucket list** model based on chained hashes with logarithmic merges — a design that has direct implications for storage efficiency.

### 1.1. Research Questions

1. **Data duplication**: Why does Horizon need its own captive core? How much storage is "wasted" vs. necessary?
2. **Bucket list vs. relational database**: How does stellar-core compress state into XDR buckets vs. how does Horizon expand it into 33 PostgreSQL tables?
3. **WAL (Write-Ahead Log)**: What is the write cost during catch-up vs. stable operation?
4. **MainNet vs. TestNet**: What is the real data volume difference between the two networks?

---

## 2. Storage Architecture (Stellar)

### 2.1. Bucket List (stellar-core)

stellar-core does not store state in a traditional database. Instead, it uses a **bucket list**:

```
Ledger N-1          Ledger N           Ledger N+1
   │                   │                   │
   ▼                   ▼                   ▼
┌──────────┐      ┌──────────┐       ┌──────────┐
│ Bucket 0 │──────│ Bucket 0'│───────│ Bucket 0"│  ← Level 0 (fresh, small)
├──────────┤      ├──────────┤       ├──────────┤
│ Bucket 1 │──────│ Bucket 1'│───────│ Bucket 1"│  ← Level 1 (merge every 64 ledgers)
├──────────┤      ├──────────┤       ├──────────┤
│    ...   │      │    ...   │       │    ...   │
├──────────┤      ├──────────┤       ├──────────┤
│ Bucket 10│──────│ Bucket 10'│──────│ Bucket 10"│ ← Level 10 (full snapshot)
└──────────┘      └──────────┘       └──────────┘
     │                   │                   │
     └───────────────────┴───────────────────┘
                         │
                         ▼
              History Archive (SDF)
         https://history.stellar.org/prd/core-live/
```

**Characteristics:**
- Each bucket is an immutable XDR file (SHA256 hash of the content = name)
- Level 0: small buckets (~25 KB) — only the changes of the current ledger
- Level 10: full state snapshot (~785 MB on MainNet)
- Every 64 ledgers, buckets from lower levels are merged into higher ones
- Old buckets are discarded (only current ones are kept)

**Storage optimization:** Buckets share data via hashes. If a bucket does not change between snapshots, its hash remains the same and it is reused (implicit deduplication).

### 2.2. Databases

| Component | Technology | Content | Estimated size (MainNet) |
|-----------|-----------|----------|---------------------------|
| Core Node | SQLite (WAL) | Ledger headers, transactions, bucket metadata | ~200 MB + buckets |
| Captive Core | SQLite (WAL) | Identical to Core Node (duplicated) | ~200 MB + buckets |
| Horizon | PostgreSQL (WAL) | Data processed into 33 tables | ~50-150 GB |
| Buckets (Core) | XDR files + index | Complete blockchain state | ~50 GB |
| Buckets (Captive) | XDR files + index | Identical to Core (duplicated) | ~50 GB |

### 2.3. Data Pipeline

```
History Archive SDF ───► Core Node ───► SQLite (current state)
                              │
                              ├──► P2P consensus (SCP)
                              │
History Archive SDF ───► Captive Core ───► SQLite (metadata)
                              │
                              ▼
                         Horizon ───► PostgreSQL (33 tables)
```

---

## 3. TestNet vs. MainNet Differences (Storage Impact)

| Characteristic | TestNet | MainNet | Impact |
|---------------|---------|---------|---------|
| **Network passphrase** | `Test SDF Network ; September 2015` | `Public Global Stellar Network ; September 2015` | None (just a string) |
| **Validators** | 3 (SDF) | 21 (SDF + LOBSTR + SatoshiPay + Blockdaemon + etc.) | +P2P traffic |
| **HOME_DOMAINS** | 1 (`testnet.stellar.org`) | 7 entities | +config |
| **History archive** | `core-testnet/core_testnet_00{N}` | `core-live/core_live_00{N}` | Endpoint |
| **Buckets (state)** | ~4.4 GB | ~50 GB estimated | **~10x larger** |
| **PostgreSQL (Horizon)** | ~4 GB (partial) | ~50-150 GB estimated | **~25x larger** |
| **Accounts** | ~2.9 million | ~7-8 million estimated | Larger volume |
| **Transactions** | ~236K ingested | Millions | Much larger |
| **Soroban (contracts)** | ~4,668 codes | Many more | State share larger |

### 3.1. Why is MainNet so much bigger?

1. **Age**: MainNet has been running since 2015; TestNet has been reset multiple times
2. **Real adoption**: MainNet has real financial transactions, asset issuers, anchors
3. **Soroban**: Smart contracts (Soroban) on MainNet have much greater adoption than on TestNet
4. **Operation volume**: MainNet processes ~5-10x more transactions per ledger

---

## 4. Modifications Made (TestNet → MainNet)

### 4.1. `docker-compose.yml`

```diff
- container_name: stellar-core
+ container_name: stellar-core-mainnet
- container_name: stellar-horizon
+ container_name: stellar-horizon-mainnet
- network: stellar-network (172.20.0.0/24)
+ network: mainnet-network (172.21.0.0/24)
- ports: 11625-11626
+ ports: 11627-11628 (avoid conflict with TestNet)
- ports: 8000
+ ports: 8001 (avoid conflict)
- NETWORK=testnet
+ NETWORK=pubnet
- volume: pgdata:/var/lib/postgresql/14/main
+ volume: pgdata:/var/lib/postgresql/16/main
```

### 4.2. `stellar-core/stellar-core.cfg`

```diff
- NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
+ NETWORK_PASSPHRASE="Public Global Stellar Network ; September 2015"
- 3 SDF testnet validators
+ 21 validators (SDF + LOBSTR + SatoshiPay + Blockdaemon + etc.)
- HOME_DOMAIN = "testnet.stellar.org"
+ 7 HOME_DOMAINs (lobstr.co, publicnode.org, satoshipay.io, ...)
- HISTORY → core_testnet_00{N}
+ HISTORY → core_live_00{N}
```

### 4.3. `stellar-horizon/stellar-captive-core.cfg`

Same changes as core.cfg (network passphrase, validators, history).

### 4.4. `stellar-horizon/horizon.env`

```diff
- # NETWORK=testnet set automatically (comment)
- # HISTORY_ARCHIVE_URLS omitted (comment)
+ export NETWORK_PASSPHRASE="Public Global Stellar Network ; September 2015"
+ export HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-live/core_live_001"
```

### 4.5. Entrypoints

Echo messages updated to reflect "MainNet" and the correct passphrase.

---

## 5. Storage Optimization Observations

### 5.1. Core vs. Captive Core Duplication

Horizon manages its own stellar-core (captive core) that downloads buckets **independently** of the main core node. This means:

- **Cost**: ~100 GB duplicated (50 GB core + 50 GB captive)
- **Benefit**: Total isolation — Horizon ingestion does not impact SCP consensus
- **Trade-off**: Acceptable for API nodes; unfeasible for low-storage devices

**Possible optimization:** Configure the captive core to reuse the core node's buckets via a read-only bind mount. However, stellar-core does not support bucket sharing between instances for consistency reasons.

### 5.2. PostgreSQL vs. SQLite

| Aspect | SQLite (Core) | PostgreSQL (Horizon) |
|---------|--------------|---------------------|
| Size | ~200 MB (data + WAL) | ~50-150 GB (data + indexes) |
| Data type | Serialized state (XDR) | Normalized relational data |
| Indexes | Few (primary key) | Many (API queries) |
| WAL | ~40-44 MB during catchup | ~400 MB+ during catchup |

**Optimization observed on TestNet:** The `accounts_signers` table is the largest in PostgreSQL (1.4 GB with indexes), surpassing the `accounts` table (873 MB). This happens because multi-sig accounts have multiple signers, each with its own record.

### 5.3. Soroban Impact on Storage

On TestNet, Soroban contract data already dominates the state:
- `PERSISTENT_CONTRACT_DATA`: 740 MB (40.2% of total state)
- `CONTRACT_CODE`: 326 MB (17.7%)
- `TTL` (Time-To-Live): 217 MB (11.8%)

**Total Soroban: ~58% of the state.** On MainNet, this share tends to be even larger.

### 5.4. WAL (Write-Ahead Log) as an Indicator

The WAL size during catch-up reveals the write intensity:
- **SQLite WAL (Core)**: 44 MB — many ledger transactions being applied
- **SQLite WAL (Captive)**: 40 MB — same process, in parallel
- **PostgreSQL WAL**: 417 MB — 16 MB per segment, ~26 segments

After catch-up, the WAL tends to stabilize at smaller sizes (~10-20% of the peak).

---

## 6. How to use

### Build and start

```bash
cd Docker-MainNet
docker-compose build --no-cache
docker-compose up -d
```

### Check status

```bash
# Core (ports 11627-11628)
curl http://localhost:11628/info

# Horizon (port 8001)
curl http://localhost:8001/
```

### Stop

```bash
docker-compose down
```

### Clean data (start from scratch)

```bash
docker-compose down -v
docker-compose up -d
```

---

## 7. Ports

| Container | Port | External | Description |
|-----------|:-----:|:-------:|-----------|
| stellar-core-mainnet | 11627 | Yes | P2P (connection with MainNet validators) |
| stellar-core-mainnet | 11628 | Yes | HTTP (admin, metrics) |
| stellar-horizon-mainnet | 8001 | Yes | Public HTTP (nginx → Horizon API) |
| stellar-horizon-mainnet | 5432 | No | PostgreSQL (internal only) |
| stellar-horizon-mainnet | 11725 | No | Captive Core P2P (internal) |
| stellar-horizon-mainnet | 11726 | No | Captive Core HTTP (internal) |

---

## 8. Volumes

| Volume | Container | Path | Estimated content |
|--------|-----------|---------|------------------|
| core-data | stellar-core-mainnet | /opt/stellar/core | SQLite + Buckets (~50 GB) |
| horizon-data | stellar-horizon-mainnet | /opt/stellar/horizon | Captive Core SQLite + Buckets (~50 GB) |
| pgdata | stellar-horizon-mainnet | /var/lib/postgresql/16/main | PostgreSQL (~50-150 GB) |

---

## 9. References

- [Stellar Bucket List Architecture](https://developers.stellar.org/docs/learn/fundamentals/bucket-list)
- [Stellar Core Config](https://developers.stellar.org/docs/run-api-server/setup/config)
- [Stellar Horizon Architecture](https://developers.stellar.org/docs/run-api-server/setup)
- [SDF Network Parameters](https://developers.stellar.org/docs/validators/list)
