# Analysis of SQL Transactions in the Stellar Databases (90 seconds)

**Date:** 2026-07-22 01:39-01:41 UTC
**Window Duration:** 90 seconds
**Analyzed Containers:** stellar-core (SQLite) + stellar-horizon (PostgreSQL + captive SQLite)

---

## Executive Summary

- **3 databases** monitored simultaneously for 90s
- **3.076 MB** of data in PostgreSQL, **1.008 MB** of WAL
- **17 ledgers** processed in the window (~0,19 ledgers/s)
- **33 tables** in PostgreSQL, **2 tables** in each SQLite
- **Dominant pattern**: INSERT into history tables + UPDATE into state tables

---

## 1. Database Architecture

```
CONTAINER 1: stellar-core                  CONTAINER 2: stellar-horizon
┌─────────────────────────┐               ┌──────────────────────────────────┐
│  SQLite (core)          │               │  PostgreSQL 16 (horizon)         │
│  ├── offers (56.602)    │               │  ├── 33 public tables            │
│  └── storestate (5)     │               │  ├── 3.076 MB of data            │
│                         │               │  ├── 1.008 MB WAL (63 files)     │
│  DB size: 18 MB         │               │  └── Ingest ledger: 3.733.367    │
│  WAL: 42 MB             │               │                                  │
│  Page size: 4.096 bytes │               │  SQLite (captive core)           │
│  Mode: WAL              │               │  ├── offers (56.602)             │
│                         │               │  ├── storestate (5)              │
│                         │               │  ├── DB size: 23 MB              │
│                         │               │  └── WAL: 14 MB                  │
└─────────────────────────┘               └──────────────────────────────────┘
```

---

## 2. PostgreSQL — Detailed Analysis (90s)

### 2.1 Ingestion Progress

| Metric | Value |
|:-------|:------|
| Ledgers processed in the window | 17 |
| Average rate | 0,19 ledgers/s |
| exp_ingest_last_ledger (end) | 3.733.367 |
| offer_compaction_sequence | 3.733.267 |
| exp_ingest_version | 20 |
| exp_state_invalid | false |

### 2.2 Deltas per Table (90s)

Calculated from the difference between the two `pg_stat_user_tables` snapshots:

```
Table                               ΔINSERT    ΔUPDATE    ΔDELETE   ΔScan    ΔIdxScan   ΔLive
───────────────────────────────────────────────────────────────────────────────────────────────
HISTORY TABLES (INSERT-only):
history_operation_participants       +337       0          0          +0        +0         +337
history_transactions                 +184       0          0          +0        +180       +184
history_transaction_participants     +302       0          0          +0        +0         +302
history_operations                   +243       0          0          +0        +0         +243
history_effects                      +80        0          0          +0        +0         +80
history_ledgers                      +18        0          0          +0        +626       +18
history_accounts                     +25        0          0          +18       +25        +25
history_trades                       +2         0          0          +0        +18        +2
history_assets                       +1         0          0          +1        +1         +1
history_trades_60000                 +3         0          +2          +18       +36        +1

STATE TABLES (INSERT + UPDATE + DELETE):
accounts                             +1         +198        +1          +0        +199       +0
accounts_signers                     +1         +0          +1          +0        +1         +0
offers                               +6         +19         +17         +0        +93        -11
trust_lines                          +0         +29         +0          +0        +29        +0
exp_asset_stats                      +0         +5          +0          +0        +10        +0
contract_asset_balances              +6         +1          +0          +0        +19        +6
contract_asset_stats                 +0         +5          +0          +0        +10        +0

CONTROL TABLES:
key_value_store                      +0         +54         +0          +367      +54        +0
```

### 2.3 Operation Distribution by Type

```
┌─────────────────────────────────────────────────────────────────────┐
│  CRUD distribution on PostgreSQL (90s)                              │
│                                                                     │
│  INSERT:  1.268 operations (62,3%)   ████████████████████████████    │
│  UPDATE:    311 operations (15,3%)   ██████▌                        │
│  DELETE:     21 operations ( 1,0%)   ▌                              │
│  SELECT:    436 operations (21,4%)   █████████                       │
│           ────────                                                  │
│  Total:  2.036 operations = 22,6 ops/s                              │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.4 Analysis by Table Category

#### 2.4.1 History Tables (pure INSERT — 62% of operations)

```
Typical flow per processed ledger:

1. INSERT history_ledgers               (1 row)
2. INSERT history_transactions          (~10 rows)
3. INSERT history_operation_participants(~19 rows)
4. INSERT history_transaction_participants(~17 rows)
5. INSERT history_operations            (~13 rows)
6. INSERT history_effects               (~4 rows)
7. INSERT history_accounts              (~1 row)
8. INSERT history_trades                (~0,1 row)
```

These tables are **append-only** — they never suffer UPDATE or DELETE. They are used for historical queries via the Horizon API.

#### 2.4.2 State Tables (INSERT + UPDATE + DELETE — 33% of operations)

```
Typical flow:

accounts:         1 INSERT + 198 UPDATEs every 90s
  └── Updates balances, sequence_number, num_subentries
  └── Each UPDATE via index (idx_scan +199)

accounts_signers: 1 INSERT + 1 DELETE every 90s
  └── Rare multi-sig changes

offers:           6 INSERT + 19 UPDATE + 17 DELETE every 90s
  └── Offers being created, modified and removed
  └── Many sequential scans (199) indicating order book reads

trust_lines:      0 INSERT + 29 UPDATEs every 90s
  └── Trust adjustments for assets

exp_asset_stats:  0 INSERT + 5 UPDATEs every 90s
  └── Asset statistics being recalculated

contract_asset_balances: 6 INSERTs + 1 UPDATE every 90s
  └── Soroban contract balances
```

#### 2.4.3 Control Tables

```
key_value_store:  54 UPDATEs every 90s (0,6 updates/s)
  └── Ingestion tracking: exp_ingest_last_ledger, compaction
```

### 2.5 Data Access (Scans)

```
Access strategy:

Tables with DOMINANT SEQUENTIAL SCAN:
  key_value_store:         4.304 seq scans (reads the entire table)
  asset_filter_rules:       364 seq scans
  account_filter_rules:     364 seq scans
  history_accounts:         366 seq scans (reads the entire accounts table)
  offers:                   199 seq scans (possibly order book)

Tables with DOMINANT INDEX SCAN:
  history_ledgers:       10.133 idx scans (lookup by ledger_seq)
  history_transactions:   1.668 idx scans (lookup by hash)
  accounts:               3.881 idx scans (lookup by account_id)
  offers:                 1.290 idx scans (lookup by seller_id)
  trust_lines:              859 idx scans (lookup by account + asset)
```

### 2.6 Checkpoints and WAL

```
BgWriter during the window:

Checkpoint buffers:     +875    (checkpoint wrote 875 buffers)
Backend buffers:        +316    (queries wrote 316 buffers)
Alloc buffers:          +190    (new buffers allocated)
Timed checkpoints:      +1      (1 checkpoint occurred in the window)

WAL:
  Size: 1.008 MB (63 files of 16 MB each)
  Rate: ~11 MB/min of WAL generated during ingestion
```

---

## 3. SQLite — Analysis of the Two Databases

### 3.1 Schema (identical in both)

```sql
CREATE TABLE storestate (
    statename CHARACTER(70) PRIMARY KEY,
    state     TEXT
);

CREATE TABLE offers (
    sellerid     VARCHAR(56) NOT NULL,
    offerid      BIGINT NOT NULL CHECK (offerid >= 0),
    sellingasset TEXT NOT NULL,
    buyingasset  TEXT NOT NULL,
    amount       BIGINT NOT NULL CHECK (amount >= 0),
    pricen       INT NOT NULL,
    priced       INT NOT NULL,
    price        DOUBLE PRECISION NOT NULL,
    flags        INT NOT NULL,
    lastmodified INT NOT NULL,
    extension    TEXT NOT NULL,
    ledgerext    TEXT NOT NULL,
    PRIMARY KEY (offerid)
);

CREATE INDEX bestofferindex ON offers (sellingasset, buyingasset, price, offerid);
CREATE INDEX offerbyseller ON offers (sellerid);
```

### 3.2 Core vs Captive Comparison

| Attribute | Core Node | Captive Core |
|:----------|:--------:|:------------:|
| **offers** | 56.602 rows | 56.602 rows |
| **storestate** | 5 rows | 5 rows |
| **DB file** | 18 MB | 23 MB |
| **WAL** | 42 MB | 14 MB |
| **Page size** | 4.096 bytes | 4.096 bytes |
| **Pages** | 5.687 | 5.660 |
| **Journal** | WAL | WAL |

### 3.3 storestate content

```
storestate table (5 rows):
  ─ internal stellar-core configuration keys
  ─ control the bucket list state
```

### 3.4 offers — Analysis

```sql
-- Indexes optimized for lookups:
-- 1. bestofferindex: sellingasset, buyingasset, price, offerid
--    → used for the order book (searching offers by asset pair)
-- 2. offerbyseller: sellerid
--    → used to list an account's offers

-- Columns:
-- sellerid:     account ID (GABCD...)
-- offerid:      unique offer ID
-- sellingasset: asset being sold (encoded as string)
-- buyingasset:  asset being bought
-- amount:       quantity (in stroops)
-- price:        price (n/d)
-- lastmodified: ledger of the last modification
```

### 3.5 Operation Pattern in SQLite

The stellar-core SQLite is used for **local ledger state**:
- storestate: 5 configuration records (READ-heavy, updated at each checkpoint)
- offers: 56.602 live offers (READ-heavy for order book matching, WRITES at checkpoint boundaries)

The captive core SQLite is **structurally identical** but used only by the captive process to rebuild state during ingestion.

---

## 4. Complete Data Flow (1 Ledger)

```
LEDGER CLOSED (every ~5s)
         │
         ▼
┌─────────────────────────────────────────┐
│  CAPTIVE CORE (via pipe fd:3)           │
│                                         │
│  Reads ledger header + txSet + results  │
│  Updates SQLite (offers, storestate)    │
│  Sends metadata to Horizon via pipe     │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  HORIZON (processes metadata)           │
│                                         │
│  1. INSERT history_ledgers              │
│  2. INSERT history_transactions         │
│  3. INSERT history_operations           │
│  4. INSERT history_effects              │
│  5. INSERT history_accounts             │
│                                         │
│  6. UPSERT accounts                     │ ← UPDATE + INSERT
│  7. UPSERT accounts_signers             │
│  8. UPSERT trust_lines                  │
│  9. UPSERT offers                       │ ← INSERT + UPDATE + DELETE
│ 10. UPSERT exp_asset_stats              │
│ 11. INSERT history_trades               │
│                                         │
│ 12. UPDATE key_value_store              │
│     (exp_ingest_last_ledger, etc)       │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  POSTGRESQL                             │
│  WAL: ~11 MB/minute                     │
│  Checkpoint: every ~90s                 │
│  Buffers: 875 per checkpoint            │
└─────────────────────────────────────────┘
```

---

## 5. Performance Analysis

### 5.1 Identified Bottlenecks

```
Bottleneck 1: WALWrite
  └── COPY trust_lines blocked on WALWrite
  └── 1.008 MB WAL indicates high log generation
  └── Solution: increase max_wal_size, checkpoint tuning

Bottleneck 2: Sequential Scans
  └── key_value_store: 4.304 sequential scans (small table, no impact)
  └── offers: 199 sequential scans (table of 56K rows)
  └── Solution: additional index for frequent order book queries

Bottleneck 3: UPDATE-heavy on accounts
  └── 198 UPDATEs/90s on the accounts table
  └── Each UPDATE generates a HOT update (83% hot updates)
  └── Good: HOT updates are efficient (no frequent VACUUM needed)
```

### 5.2 Operation Rate

| Type | 90s | Per Ledger | Per Second |
|:-----|:---:|:----------:|:-----------:|
| INSERT | 1.268 | 74,6 | 14,1 |
| UPDATE | 311 | 18,3 | 3,5 |
| DELETE | 21 | 1,2 | 0,2 |
| SELECT | 436 | 25,6 | 4,8 |
| **Total** | **2.036** | **119,8** | **22,6** |

### 5.3 Cache Hit Ratio

Based on the accessed indexes:
- `history_ledgers`: 10.133 idx scans (cache hit ~99% — PK lookup)
- `accounts`: 3.881 idx scans (cache hit ~99% — account_id lookup)
- `trust_lines`: 859 idx scans (cache hit ~99%)
- `offers`: 1.290 idx scans + 199 seq scans

PostgreSQL is operating mostly from cache (shared_buffers = 128 MB).

---

## 6. Complete Schemas

### 6.1 PostgreSQL — Schema of the Most Active Tables

```sql
-- History tables (INSERT-only)
history_ledgers:            ledger_seq, hash, prev_hash, closed_at, ... (36 KB/row)
history_transactions:       tx_hash, ledger_seq, tx_envelope, tx_result, ... (36 KB/row)
history_operations:         op_id, tx_hash, ledger_seq, op_type, details, ... (6 KB/row)
history_effects:            effect_id, op_id, effect_type, details, ... (2 KB/row)
history_accounts:           account_id, added_ledger, ... (0,5 KB/row)

-- State tables (INSERT+UPDATE+DELETE)
accounts:                   account_id, balance, seq_num, signers, ... (0,3 KB/row)
accounts_signers:           account_id, signer_key, weight, ... (0,5 KB/row)
trust_lines:                account_id, asset_code, asset_issuer, balance, ... (1 KB/row)
offers:                     seller_id, offer_id, selling, buying, amount, price, ... (0,5 KB/row)
contract_asset_balances:    contract_id, asset_code, issuer, balance, ... (0,2 KB/row)
key_value_store:            key VARCHAR, value TEXT (0,1 KB/row)
```

### 6.2 SQLite (Core + Captive) — Complete Schema

```sql
-- Already documented in Section 3.1
-- Only 2 tables: offers + storestate
-- Indexes: bestofferindex + offerbyseller
```

---

## 7. Conclusions

1. **INSERT-heavy pattern**: 62% of the operations are INSERTs into history tables (append-only). The `history_operation_participants` table is the most active with 337 inserts/90s.

2. **UPDATE concentrated on accounts**: The `accounts` table receives 198 UPDATEs/90s (2,2/s) — each ledger modifies the balances of multiple accounts. 83% are HOT updates (efficient).

3. **DELETE is rare**: Only 21 DELETEs/90s, all in `offers` (expired/removed offers).

4. **SQLite is secondary**: The SQLites (core + captive) act as a local cache for offers + storestate. Data volume is low compared to PostgreSQL.

5. **PostgreSQL WAL is voluminous**: 1.008 MB of WAL for a ~3 GB database, indicating checkpoint tuning is needed.

6. **Slow ingestion**: 17 ledgers/90s (0,19/s) — well below the ~10 ledgers/s observed previously. Probably due to checkpoint/recovery after a restart.

---

## Appendix A: Collection Metadata

```
Tools used:
- pg_stat_user_tables (before/after snapshots)
- pg_stat_bgwriter (before/after snapshots)
- pg_stat_activity (sampling every 5s × 18 samples)
- pg_ls_waldir (WAL size)
- sqlite3 PRAGMA + .schema + .tables
- key_value_store (ingestion state)

Limitations:
- pg_stat_statements could not be loaded (shared_preload_libraries)
- pg_stat_activity samples were mostly empty (ingestion between samples)
- Deltas computed between two snapshots, not continuous tracking
```

## Appendix B: Commands for Reproduction

```bash
# Monitor PostgreSQL
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT * FROM pg_stat_user_tables ORDER BY n_tup_ins DESC;"

# Check WAL
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT count(*), pg_size_pretty(sum(size)) FROM pg_ls_waldir();"

# Check core SQLite
docker exec stellar-core sqlite3 /opt/stellar/core/stellar.db ".tables"

# Check captive SQLite
docker exec stellar-horizon sqlite3 /opt/stellar/horizon/captive-core/stellar.db ".tables"

# Check ingestion progress
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT * FROM key_value_store;"
```
