# Complete Report on Stellar Testnet Node Synchronization and State

**Experiment Date:** 2026-07-20 (executed on 2026-07-21 02:00 UTC)
**Container:** stellar-testnet (stellar/quickstart:testing)
**Core Version:** v27.1.0 — Protocol 27
**Network:** Test SDF Network ; September 2015
**State at Start:** Connected / Catching up (~2,8 days behind)
**State at End:** Synced!

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Bucket Analysis](#2-bucket-analysis)
3. [PostgreSQL Database Analysis (Horizon)](#3-postgresql-database-analysis-horizon)
4. [Checkpoint Structure](#4-checkpoint-structure)
5. [Database Activity Monitoring (90s)](#5-database-activity-monitoring-90s)
6. [Smart Contract Analysis (Soroban)](#6-smart-contract-analysis-soroban)
7. [Network and Consensus Metrics](#7-network-and-consensus-metrics)
8. [Storage and System Resources](#8-storage-and-system-resources)
9. [Complete Data Flow](#9-complete-data-flow)
10. [Conclusions](#10-conclusions)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DOCKER CONTAINER                             │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐             │
│  │  Stellar     │   │  Captive     │   │  Horizon     │             │
│  │  Core Node   │   │  Core        │   │  API         │             │
│  │  (PID 118)   │   │  (PID 310)   │   │  (PID 168)   │             │
│  │              │   │              │   │              │             │
│  │ Port: 11626  │   │ Port: 11726  │   │ Port: 8001   │             │
│  │ P2P: 11625   │   │ P2P: 11725   │   │              │             │
│  │              │   │              │   │              │             │
│  │ SQLite:      │   │ SQLite:      │   │ PostgreSQL:  │             │
│  │ stellar.db   │   │ stellar.db   │   │ horizon (4.9GB)            │
│  │ Buckets:4.3GB│   │ Buckets:4.3GB│   │              │             │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘             │
│         │                  │                  │                     │
│         │ P2P SCP         │ Pipe (fd:3)      │ HTTP API             │
│         ▼                  ▼                  ▼                     │
│  ┌──────────────────────────────────────────────────────┐           │
│  │                  nginx (port 8000)                    │           │
│  │            Reverse proxy: / → Horizon :8001           │           │
│  └──────────────────────────────────────────────────────┘           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────┐           │
│  │         History Archives (SDF) — Data downloads       │           │
│  │  https://history.stellar.org/prd/core-testnet/       │           │
│  └──────────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

### Running Processes

| Process | PID | CPU% | MEM% | RSS |
|:--------|:----|:-----|:-----|:----|
| Captive Core (Horizon) | 310 | 60,7% | 18,3% | ~2,99 GB |
| Stellar Core | 118 | 47,1% | 16,7% | ~2,74 GB |
| Horizon | 168 | 8,7% | 0,6% | ~102 MB |
| PostgreSQL | 255 | 0,3% | 0,3% | ~55 MB |
| supervisord (PID 1) | 1 | 0,3% | 0,1% | ~28 MB |

---

## 2. Bucket Analysis

### 2.1 What are Buckets

Buckets are XDR files that store **snapshots of the complete state** of the Stellar ledger. The bucket list is organized into **merge levels** (L0 to L5+), where higher levels contain more consolidated and older data.

```
Bucket Levels:

L0 (fresh) ─── Small (<1 MB) ─── 22 files ─── New, unmerged data
L1 ──────────── 1-10 MB ─────────── 6 files ─── Partial merge
L2 ──────────── 10-100 MB ────────── 7 files ─── Intermediate merge
L3 ──────────── 100-202 MB ──────── 4 files ─── Consolidated
L4 ──────────── 200-452 MB ──────── 4 files ─── Deep
L5 (snap) ───── 600-785 MB ──────── 3 files ─── Complete snapshot
```

### 2.2 Bucket Inventory — Core Node

Distribution of the 49 `.xdr` files in `/opt/stellar/core/buckets/`:

```
Size       │ Quantity │ Level  │ Creation Period
───────────┼──────────┼────────┼─────────────────────
785 MB     │     1    │  L5    │ 16/07 01:04
610 MB     │     1    │  L5    │ 16/07 01:02
600 MB     │     1    │  L5    │ 16/07 01:04
452 MB     │     1    │  L4    │ 16/07 01:02
355 MB     │     1    │  L4    │ 16/07 01:02
310 MB     │     1    │  L4    │ 16/07 01:01
266 MB     │     1    │  L4    │ 16/07 00:58
202 MB     │     1    │  L3    │ 16/07 01:00
192 MB     │     1    │  L3    │ 16/07 01:04
153 MB     │     1    │  L3    │ 16/07 01:00
121 MB     │     1    │  L3    │ 16/07 00:58
 98 MB     │     1    │  L2    │ 16/07 01:04
 69 MB     │     1    │  L2    │ 16/07 00:59
 55 MB     │     1    │  L2    │ 18/07 00:34
 30 MB     │     1    │  L2    │ 18/07 00:40
 25 MB     │     1    │  L2    │ 16/07 00:58
 20 MB     │     1    │  L2    │ 18/07 00:42
 14 MB     │     1    │  L2    │ 18/07 00:34
 <10 MB    │    28    │  L0-L1  │ 18-19/07
 ────────  │ ──────── │         │
 4,27 GB   │    49    │ Total   │
```

### 2.3 Distribution by Content (Bucket List)

Data obtained from stellar-core metrics, representing the complete network state:

```
Testnet State Composition:

PERSISTENT_CONTRACT_DATA   4.193.309 entries (716 MB)  ████████████████████████████████████████ 40,2%
ACCOUNT                    2.956.700 entries (374 MB)  ████████████████████████████████████████ 21,0%
CONTRACT_CODE                 22.544 entries (304 MB)  ████████████████████████████████████████ 17,1%
TTL                        4.356.785 entries (208 MB)  ████████████████████████████████████████ 11,7%
DATA (account)               332.654 entries ( 49 MB)  ████████████████████████████████████████  2,8%
TRUSTLINE                    325.706 entries ( 45 MB)  ████████████████████████████████████████  2,5%
TEMPORARY_CONTRACT_DATA      143.452 entries ( 22 MB)  ████████████████████████████████████████  1,2%
OFFER                         53.382 entries (  9 MB)  ████████████████████████████████████████  0,5%
CLAIMABLE_BALANCE             8.918 entries (  2 MB)   ████████████████████████████████████████  0,1%
LIQUIDITY_POOL                2.592 entries (422 KB)   ████████████████████████████████████████ <0,1%
CONFIG_SETTING                   40 entries (  5 KB)   ████████████████████████████████████████ <0,1%

Soroban (PERSISTENT_CONTRACT + CONTRACT_CODE + TTL + TEMPORARY): ~70,1% of state
Non-Soroban (ACCOUNT + DATA + TRUSTLINE + OFFER + etc.):          ~29,9% of state
```

### 2.4 Captive Core vs Core Node Buckets

The Horizon Captive Core keeps **independent** buckets in `/opt/stellar/horizon/captive-core/captive-core/buckets/`.

```
Comparison:

                    Core Node    Captive Core     Duplication
.xdr files:         49           43               25 identical hashes
Total size:         4,272 GB     4,273 GB          ~4,1 GB duplicated
.index files:       30 (86 MB)   0                —
Sentinel bucket:    1 (20 bytes) 1 (20 bytes)     —

Total bucket storage cost: ~8,5 GB (2x due to the isolation architecture)
```

### 2.5 Top 5 Largest Buckets

```
File                                              Size      Level
bucket-ff26b4f5...7efd.xdr                    785 MB     L5 (deepest snapshot)
bucket-eb7625ce...4b72.xdr                    610 MB     L5
bucket-d8522ede...2d730.xdr                   600 MB     L5
bucket-8a27deda...b125.xdr                    452 MB     L4
bucket-b2a2c09a...d09b.xdr                    355 MB     L4
```

---

## 3. PostgreSQL Database Analysis (Horizon)

### 3.1 Overview

| Database | Size | Connection |
|:---------|:-----|:-----------|
| **horizon** | **4.924 MB** (~4,8 GB) | localhost:5432 |
| postgres | 8.441 kB | template |
| template0 | 8.441 kB | template |
| template1 | 8.441 kB | template |

### 3.2 All Tables by Size

```
Table                                       Total Size   Indexes   Rows (est.)
───────────────────────────────────────────────────────────────────────────────
accounts_signers                            1.433 MB      1.002 MB     2.977.063
history_transactions                        1.316 MB         73 MB      417.503
accounts                                      877 MB        375 MB    2.899.477
history_operations                            403 MB         25 MB      612.480
trust_lines                                   282 MB        172 MB      325.706
accounts_data                                 221 MB        126 MB      332.688
history_operation_participants                 87 MB         49 MB      858.132
history_effects                                72 MB         22 MB      242.846
history_transaction_participants               70 MB         38 MB      684.934
history_ledgers                                36 MB         1,7 MB      36.421
offers                                         35 MB         22 MB       47.440
exp_asset_stats                                35 MB         11 MB       53.913
contract_asset_balances                        13 MB          6 MB       56.663
claimable_balances                             12 MB          7 MB        8.747
claimable_balance_claimants                    12 MB          9 MB       18.455
history_accounts                            6.440 kB          —         25.666
liquidity_pools                             1.792 kB          —          2.577
history_trades                              1.216 kB          —          1.620
history_trades_60000                          520 kB          —          1.446
asset_contracts                               512 kB          —            695
contract_asset_stats                          320 kB          —          1.191
remaining (13 tables)                      ~600 kB          —         <1.000 each
───────────────────────────────────────────────────────────────────────────────
Total (33 tables):                         4.924 MB          —        ~9,3M rows
```

### 3.3 Exact Row Counts

```
Table                        Rows
────────────────────────────────
accounts                   2.918.298
accounts_signers           2.997.226
trust_lines                   327.289
offers                         53.382
history_ledgers                39.328
history_transactions          432.432
history_operations            642.487
history_effects               249.575
history_trades                  1.832
liquidity_pools                 2.592
claimable_balances              8.918
contract_asset_balances        57.698
contract_asset_stats            1.191
asset_contracts                   695
────────────────────────────────
```

### 3.4 Ingestion State (`key_value_store`)

| Key | Value |
|:----|:------|
| exp_state_invalid | false |
| exp_ingest_version | 20 |
| exp_ingest_last_ledger | 3.672.313 |
| offer_compaction_sequence | 3.672.213 |
| liquidity_pool_compaction_sequence | 3.672.213 |

### 3.5 Latest Ingested Ledgers

| Ledger Seq | Hash | Closed At |
|:-----------|:-----|:----------|
| 3.668.639 | e3e06cf2... | 2026-07-18 07:39:05 |
| 3.668.638 | 767599e0... | 2026-07-18 07:39:00 |
| 3.668.637 | 5630ae71... | 2026-07-18 07:38:55 |
| 3.668.636 | 6c9c2015... | 2026-07-18 07:38:50 |
| 3.668.635 | dc0d91e1... | 2026-07-18 07:38:45 |

---

## 4. Checkpoint Structure

### 4.1 What is a Checkpoint

A Stellar checkpoint groups **64 consecutive ledgers** (~5 minutes and 20 seconds of network activity). At each checkpoint, the node publishes files to the history archive containing the complete history of that interval.

```
Checkpoint N ─── 64 ledgers ─── Covers ~5 min 20s of the network
  │
  ├── Chunk 1: ledgers 0-15
  ├── Chunk 2: ledgers 16-31
  ├── Chunk 3: ledgers 32-47
  └── Chunk 4: ledgers 48-63
```

### 4.2 Checkpoint Files

For each checkpoint, the following files are stored in the history archive:

```
URL: https://history.stellar.org/prd/core-testnet/core_testnet_001/
                        │
        ┌───────────────┴───────────────┐
        │                               │
  history-XXXX.json             XX/YY/ZZ/
        │                               │
  stellar-history.json     ┌─────┬──────┼──────┬─────┐
                          │     │      │      │     │
                     ledger/ txs/  results/ scp/ buckets/

Directory structure in the archive:
  XX/YY/ZZ/ledger/ledger-XXXXYYff.xdr    (4 chunks: 3f, 7f, bf, ff)
  XX/YY/ZZ/transactions/transactions-XXXXYYff.xdr
  XX/YY/ZZ/results/results-XXXXYYff.xdr
  XX/YY/ZZ/scp/scp-XXXXYYff.xdr
```

Where `XXXXYY` = checkpoint number in hex, and `XX/YY/ZZ` = first 6 hex digits in pairs.

### 4.3 Content of Each File

```
ledger-*.xdr
  └── Sequence of LedgerHeaderHistoryEntry
      ├── Ledger hash
      ├── LedgerHeader (ledgerVersion, ledgerSeq, previousLedgerHash, scpValue,
      │                 txSetResultHash, bucketListHash, totalCoins,
      │                 feePool, baseFee, baseReserve, maxTxSetSize, ...)
      └── Extension

transactions-*.xdr
  └── Sequence of TransactionHistoryEntry
      ├── ledgerSeq
      ├── TransactionEnvelopeList (all transactions of the chunk)
      │   ├── Envelope V1 (regular)
      │   │   ├── tx: sourceAccount, fee, seq, timeBounds, operations[], memo
      │   │   ├── signatures[]
      │   │   └── SorobanData (resources: instructions, readBytes, writeBytes)
      │   └── Envelope V0 (legacy)
      └── Results (optional extension)

results-*.xdr
  └── Sequence of TransactionHistoryResultEntry
      ├── ledgerSeq
      └── TransactionResultPairList
          ├── TransactionResult (success/failure)
          │   ├── feeCharged
          │   ├── result code
          │   ├── operations[]
          │   │   ├── tr (operation-specific result code)
          │   │   └── SorobanMeta (events[], returnValue, diagnosticEvents)
          │   └── ext (Soroban: events[], returnValue, diagnosticEvents)
          └── (hash of the corresponding tx)

scp-*.xdr
  └── Sequence of SCPHistoryEntry
      ├── SCP envelopes (nominate, prepare, confirm, externalize)
      ├── Quorum set
      └── Validator votes and confirmations
```

### 4.4 Frequency on the Testnet

```
Ledgers per checkpoint:  64
Time per ledger:         ~5 seconds
Time per checkpoint:     ~5 min 20s
Current ledger:          3.672.375
Current checkpoint:      57.381 (3.672.375 ÷ 64)
```

### 4.5 Referenced Buckets

The `stellar-history.json` file references the hashes of the buckets that compose the ledger state snapshot at the checkpoint:

```
stellar-history.json
  ├── version: 2
  ├── server: "stellar-core 27.1.0"
  ├── currentLedger: <number>
  ├── networkPassphrase: "Test SDF Network ; September 2015"
  └── currentBuckets[]
      ├── level 0: curr=<hash>, snap=<hash>, next={state}
      ├── level 1: curr=<hash>, snap=<hash>, next={state}
      ├── ...
      ├── level 5: curr=<hash>, snap=<hash>, next={state}
      └── hotArchiveBuckets[]
```

---

## 5. Database Activity Monitoring (90s)

### 5.1 Ledger Progress During the Window

During the 90 seconds of monitoring, the node processed **910 new ledgers** (~10 ledgers/second):

```
Metric                  Before (T1)    After (T2)    Δ
Core latest            3.671.465      3.672.375     +910
Ingest latest          3.671.464      3.672.374     +910
History latest         3.671.464      3.672.374     +910
exp_ingest_last_ledger 3.671.455      3.672.313     +858
offer_compaction       3.671.355      3.672.213     +858
```

### 5.2 Activity per Table (Δ in 90 seconds)

```
Table                                   Δ Inserts   Δ Updates   Δ Deletes   Δ Live
─────────────────────────────────────────────────────────────────────────────────────
history_operation_participants              +17.445          0           0     +17.445
history_transaction_participants            +13.491          0           0     +13.491
history_operations                          +12.109          0           0     +12.109
history_transactions                        +7.781           0           0     +7.781
history_effects                             +5.861           0           0     +5.861
history_ledgers                               +800           0           0       +800
offers                                        +578        +596        +550         +28
history_accounts                              +449           0           0        +449
trust_lines                                   +458      +2.106         +33        +425
accounts                                      +416      +8.272         +96        +320
accounts_signers                              +416           0         +97        +319
history_trades_60000                          +312           0        +263         +49
claimable_balance_claimants                   +243           0         +28        +215
claimable_balances                            +108           0         +14         +94
contract_asset_balances                        +34        +171         +80          +5
exp_asset_stats                                +32        +360           0         +32
key_value_store                                 0      +2.400           0           0
contract_asset_stats                            0         +215           0           0
─────────────────────────────────────────────────────────────────────────────────────
Total inserts:                             ~60.000
Total updates:                             ~14.000
Total database operations:                 ~74.000 in 90s (~822 ops/s)
```

### 5.3 Visualization of the Operation Rate

```
Database operation rate (per second over 90s):

                  ┌──────┐
history_op_partic ┤ ████████████████████████████████████████████████████  194/s
history_tx_partic ┤ ██████████████████████████████████████████████████    150/s
history_operations┤ ███████████████████████████████████████████████      135/s
history_transactns┤ ██████████████████████████████████████                86/s
history_effects   ┤ █████████████████████████████                        65/s
accounts (upd)    ┤ ████████████████████████████████████████████████████   92/s
accounts (ins)    ┤ █████▌                                                  5/s
trust_lines (upd) ┤ ██████████                                             23/s
key_value_store   ┤ ███████████                                            27/s
contract_asset_st ┤ ██▌                                                     2/s
──────────────────┴──────────────────────────────────────────────────────────
                   Total: ~822 operations/second on the database
```

### 5.4 Ingestion Pattern

```
Horizon ingestion flow for each ledger:

1. New ledger arrives from the Captive Core via pipe
2. INSERT history_ledgers          (+1)
3. INSERT history_transactions     (+~8,5 txs/ledger)
4. INSERT history_operations       (+~13,3 ops/ledger)
5. INSERT history_effects          (+~6,4 effects/ledger)
6. INSERT/UPDATE accounts          (+0,45 + ~9,1 updates/ledger)
7. INSERT/UPDATE trust_lines       (+0,5 + ~2,3 updates/ledger)
8. INSERT/UPDATE offers            (+0,6 + ~0,6 updates/ledger)
9. INSERT participants             (+~19 + ~15/ledger)
10. UPDATE key_value_store         (+~2,6/ledger)
11. UPDATE contract_asset_stats    (+~0,2/ledger)
12. (every 100 ledgers) UPDATE exp_ingest_last_ledger
```

---

## 6. Smart Contract Analysis (Soroban)

### 6.1 Where Soroban Data Resides

Soroban stores data in **three distinct layers**:

```
              ┌─────────────────────────────────────────────────────────────────┐
              │                   BUCKETS (Stellar Core)                        │
              │                Primary Ledger Storage                           │
              │                                                                 │
              │  ┌──────────────────────────────────────────────────────────┐   │
              │  │  PERSISTENT_CONTRACT_DATA   4.193.309 entries  716 MB   │   │
              │  │  CONTRACT_CODE                 22.544 entries  304 MB   │   │
              │  │  TTL                         4.356.785 entries  208 MB  │   │
              │  │  TEMPORARY_CONTRACT_DATA       143.452 entries   22 MB  │   │
              │  │                                         Total: 1,25 GB  │   │
              │  └──────────────────────────────────────────────────────────┘   │
              └─────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │               SQLITE (Stellar Core)                            │
              │            Transient Operational Metadata                       │
              │                                                                 │
              │  stellar.db (21 MB) — no contract-specific data                 │
              │  Only tables: offers, storestate                               │
              └─────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │             POSTGRESQL (Horizon)                               │
              │            Indexed Historical Data for Query                    │
              │                                                                 │
              │  contract_asset_balances   57.698 rows    13 MB                 │
              │  contract_asset_stats       1.191 rows   320 KB                 │
              │  asset_contracts              695 rows   512 KB                 │
              │  history_operations (types 24, 25, 26)  303.527 rows            │
              └─────────────────────────────────────────────────────────────────┘
```

### 6.2 Soroban Operation Types in History

```
Distribution of Soroban operations in history_operations:

Type 24 — invokeHostFunction     303.527   ████████████████████████████████████████████████ 98,5%
Type 25 — extendFootprintTTL       4.565   █▌                                                1,5%
Type 26 — restoreFootprint            13   ▎                                                 <0,1%
                                   ───────
Total Soroban:                   308.105

Comparison with non-Soroban operations:
  Total operations in history:  630.422
  Soroban:                       308.105  (48,9%)
  Non-Soroban:                   322.317  (51,1%)
```

### 6.3 Soroban Module Cache (in memory)

Stellar Core keeps a RAM cache of compiled WASM modules:

```
soroban.module-cache.num-entries:    4.625 contracts in cache
soroban.module-cache.rebuild-bytes:  124.919.414 bytes (~119 MB)
soroban.module-cache.rebuild-time:   6.493 ms (a single rebuild)
soroban.module-cache.compil-time:      53 ms cumulative
```

### 6.4 Contracts vs Accounts

```
Comparison of Soroban contracts vs traditional accounts:

                            Soroban          Non-Soroban
Counts:
  Bucket list entries:     8.716.090 (70%)   3.660.175 (30%)
  Bucket storage:          1.250 MB (70%)      533 MB (30%)
  Operations in history:     308.105 (49%)     322.317 (51%)

Success rate:
  Successful applies:          18.692           23.634
  Failures:                       123                0
  Success rate:               99,35%            100%

Limits:
  Max tx size:            132.096 bytes      (limited by ledger)
  Max CPU instructions:   400.000.000        (not applicable)
  Max memory:             41.943.040 bytes   (not applicable)
  Max read entries:                200      (not applicable)
  Max write entries:               200      (not applicable)
```

### 6.5 Soroban Transaction Processing Flow

```
Soroban transaction enters the mempool
         │
         ▼
┌─────────────────────┐
│  1. Herder receives │────→ Verifies fee, seq, signature
│     the transaction │      Verifies footprint (ledger keys accessed)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  2. SCP leader      │────→ Includes in txSet (max 2.000 Soroban txs)
│     proposes set    │      Limit of 266.240 Soroban bytes/ledger
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  3. SCP consensus   │────→ Nominate → Prepare → Confirm → Externalize
│     (all nodes)     │      SCP envelopes signed by validators
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  4. Apply ledger    │────→ 4 stages (soroban.stages=1 max-clusters=1)
│                     │
│  4a. Loads WASM     │────→ Module cache hit? If not: compiles WASM
│                      │      (4.625 modules in cache, 119 MB)
│  4b. Verifies       │────→ Read footprint: tx-max-read-entry=200
│      footprint      │      Read-ledger-byte: 200.000 bytes
│  4c. Executes       │────→ WASM VM executes host function
│      contract       │      Instruction count: max 400M
│                      │      Memory: max 40 MB per transaction
│  4d. Writes         │────→ Write footprint: tx-max-write-entry=200
│      results        │      Write-ledger-byte: 132.096 bytes
│  4e. Emits events   │────→ tx-max-emit-event-byte: 16.384
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  5. Invariant       │────→ Invariants: 0 failures
│     verification    │      Soroban: 18.698 successes, 123 failures
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  6. Commit to       │────→ Bucket list: merge from L0 upward
│     buckets         │      TTL managed via extendFootprintTTL
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  7. Horizon         │────→ Captive core → pipe → PostgreSQL
│     ingests         │      INSERT history + UPDATE current state
│     metadata        │
└─────────────────────┘
```

---

## 7. Network and Consensus Metrics

### 7.1 P2P Connection State

```
Network status at collection time:

Authenticated peers:           3              (sdf_testnet_1, 2, 3)
Pending peers:                 55
Outbound attempts:             177            (98% churn: 174 drops)
Idle timeouts:                 160
Straggler timeouts:            0
```

### 7.2 Network Traffic

```
P2P traffic since node start:

Metric                    Received    Sent
Bytes                      496.464     66.372
Messages                     1.210        251
SCP messages                  881        127
  scp-nominate               260
  scp-prepare                318
  scp-confirm                 83
  scp-externalize            220

Flood:
  Unique messages received:         128.740
  Duplicate messages received:     223.320
  Messages broadcast:                   127
```

### 7.3 SCP Consensus

```
SCP envelopes received:             1.014
SCP envelopes signed:                  28
SCP envelopes validated OK:           481
SCP envelopes invalid:                  0
SCP envelopes fetch:                   133 (avg 86,4ms)
Nominate timeouts:                       7
Prepare timeouts:                         7
Ballot blocked on txset:                 7
Sync lost:                                1
```

### 7.4 Cryptographic Verifications

```
Total SHA256 verifications:    1.685
  Hit (cache):                 1.311
  Miss:                           374
Transaction verifications:         0 (node in catchup)
```

---

## 8. Storage and System Resources

### 8.1 Total Storage

```
/opt/stellar/              15,0 GB
│
├── core/                   4,6 GB   ── Stellar Core Node
│   ├── buckets/            4,4 GB   ── 49 .xdr files + 30 .index
│   ├── stellar.db          21  MB   ── SQLite (ledgers + storestate)
│   ├── stellar.db-wal      44  MB   ── Write-Ahead Log
│   └── stellar.db-shm      64  KB   ── Shared Memory
│
├── horizon/                4,7 GB   ── Captive Core (Horizon)
│   ├── captive-core/       4,6 GB   ── replicated buckets
│   │   ├── buckets/        4,3 GB   ── 43 .xdr files
│   │   └── stellar.db      21  MB   ── own SQLite
│   └── ...
│
├── postgresql/             5,3 GB   ── PostgreSQL (Horizon data)
│   └── base/horizon        4,9 GB   ── 33 tables, ~9,3M rows
│
├── lab/                   171  MB   ── Stellar Lab
└── others (nginx,          200 KB
     supervisord, friendbot,
     stellar-rpc, galexie)
```

### 8.2 Hardware Resources

```
Total RAM:       15,0 GB
RAM in use:       6,6 GB  (44%)
Free RAM:         2,2 GB
Buffer/Cache:     7,1 GB

Total swap:       4,0 GB
Swap in use:      0      (no swap)

CPU:              Captive Core 60,7% + Core Node 47,1% + Horizon 8,7%
                  ≈ 117% CPU used (containers have no limit)

Disk (Docker):   1.007 GB total, 34 GB used (4%)
```

---

## 9. Complete Data Flow

### 9.1 Pipeline from Ledger to Database

```
History Archives (SDF)
  https://history.stellar.org/prd/core-testnet/
         │
         ├─────────────────────┬──────────────────────┐
         ▼                     ▼                      ▼
┌────────────────┐   ┌────────────────┐   ┌──────────────────────┐
│ Core Node      │   │ Captive Core   │   │ Horizon              │
│                │   │                │   │                      │
│ Downloads     │   │ Downloads     │   │ Reads metadata via    │
│ buckets       │   │ buckets       │   │ pipe fd:3 from the    │
│ Downloads     │   │ Downloads     │   │ captive core          │
│ checkpoints   │   │ checkpoints   │   │                      │
│ SCP Consensus │   │ (no SCP)      │   │                      │
│                │   │                │   │                      │
│ Local SQLite  │   │ Local SQLite  │   │ PostgreSQL           │
│ stellar.db    │   │ stellar.db    │   │ 33 tables            │
│ buckets/      │   │ buckets/      │   │ 4,9 GB of data       │
└───────┬────────┘   └───────┬────────┘   └──────────────────────┘
        │                    │                        ▲
        │ P2P (SCP)         │ Pipe (metadata output   │
        │                    │   stream fd:3)          │
        │                    ▼                         │
        │          ┌─────────────────────┐            │
        │          │ For each ledger:   │────────────┘
        │          │  - LedgerHeader    │
        │          │  - TxSet           │
        │          │  - TxProcessing    │
        │          │  - Operations      │
        │          │  - Effects         │
        │          │  - AccountChanges  │
        │          │  - Trades          │
        │          │  - SorobanMeta     │
        │          └─────────────────────┘
        │
        ▼
┌───────────────────┐
│ P2P Network       │
│ 3 SDF validators  │
│ core-testnet1..3  │
│ port 11625        │
└───────────────────┘
```

### 9.2 Soroban Data Pipeline

```
Soroban transaction (e.g., invokeHostFunction)
         │
         ▼
┌───────────────────────────────────────────────────┐
│               1. MEMPOOL (Herder)                  │
│  pending-soroban-txs: 0 (no backlog currently)    │
│  maxSorobanTxSetSize: 2.000 transactions/ledger   │
└─────────────────────┬─────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│             2. EXECUTION (WASM VM)                 │
│                                                     │
│  ┌──────────┐   ┌──────────┐   ┌───────────────┐   │
│  │ Module   │   │ Footprint│   │ Host Function │   │
│  │ Cache    │──▶│ Check    │──▶│ Execution     │   │
│  │ 4.625    │   │ 200 rd   │   │ WASM sandbox  │   │
│  │ contracts│   │ 200 wr   │   │ max 400M inst │   │
│  └──────────┘   └──────────┘   └───────┬───────┘   │
│                                        │           │
│                              ┌─────────▼───────┐   │
│                              │    Result:       │   │
│                              │  - return value  │   │
│                              │  - events        │   │
│                              │  - diagnostic    │   │
│                              │  - state changed │   │
│                              └─────────────────┘   │
└───────────────────────────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│          3. COMMIT TO BUCKETS                      │
│                                                     │
│  BucketList:                                        │
│  L0 ── merge ──▶ L1 ── merge ──▶ ... ──▶ L5       │
│                                                     │
│  Entries written:                                   │
│  - PERSISTENT_CONTRACT_DATA  (716 MB)              │
│  - CONTRACT_CODE              (304 MB)              │
│  - TTL                        (208 MB)              │
│  - TEMPORARY_CONTRACT_DATA     (22 MB)              │
└───────────────────────────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│        4. INGESTION IN HORIZON (PostgreSQL)        │
│                                                     │
│  Tables updated:                                    │
│  - history_operations (types 24, 25, 26)           │
│  - contract_asset_balances (57.698 rows)            │
│  - contract_asset_stats (1.191 rows)                │
│  - asset_contracts (695 rows)                       │
└───────────────────────────────────────────────────┘
```

---

## 10. Conclusions

1. **Soroban dominates the Testnet state.** 70% of the ledger entries (~8,7M of ~12,4M) and 70% of the bucket storage are smart contracts. The Testnet has intense contract activity, with 22.544 unique WASM codes in cache.

2. **Bucket duplication (8,5 GB) between Core Node and Captive Core** is intentional to isolate consensus (Core Node) from data ingestion (Horizon), but it represents 57% of the node's total storage.

3. **PostgreSQL consumes 4,9 GB** across 33 tables and ~9,3M rows. The heaviest table is `accounts_signers` (1,4 GB), reflecting the multi-sig nature of Stellar.

4. **Rate of 822 operations/second on the database** during catch-up, peaking at 194 inserts/s on `history_operation_participants`. The node processes ~10 ledgers/second in catch-up mode.

5. **Checkpoints store 4 types of XDR files** (ledger headers, transactions, results, SCP) organized into 16-ledger chunks. Each checkpoint covers 64 ledgers (~5 min 20s).

6. **The Soroban Module Cache (4.625 contracts, 119 MB)** keeps compiled WASM in RAM, avoiding recompilation on repeated contract calls. It was rebuilt once in 6,5 seconds.

7. **48% of all historical operations are Soroban** (303.527 invokeHostFunction + 4.578 TTL/restore), indicating that smart contract activity is already comparable to traditional payment activity on the Testnet.

---

## Appendix A: XDR Structure of a Bucket

```
Bucket XDR header (first 16 bytes):

80 00 00 10    ── XDR Discriminant (LedgerEntry)
ff ff ff ff    ── Number of entries (-1 = continuation flag)
00 00 00 1b    ── Protocol 27 (0x1b = 27)
00 00 00 01    ── Flags (initialization)
```

## Appendix B: Commands Used for Data Collection

```bash
# Node info
curl -s http://localhost:11626/info

# Full metrics
curl -s http://localhost:11626/metrics

# List buckets
ls -lhS /opt/stellar/core/buckets/*.xdr

# Supervisor status
supervisorctl status

# PostgreSQL query
psql -h localhost -U stellar -d horizon -c "SELECT ..."

# SQLite query
sqlite3 /opt/stellar/core/stellar.db "SELECT ..."

# Horizon status
curl -s http://localhost:8001/
```

## Appendix C: Frequently Asked Questions (FAQ)

### Why does the percentage oscillate during catch-up?
New ledgers are produced by the network every ~5s, increasing the denominator of the progress calculation while the node processes old checkpoints. The calculated percentage is `(remaining / total_current)`, where `total_current` grows continuously (moving target).

### How many checkpoints need to be downloaded?
It depends on the most recent available bucket snapshot. With `CATCHUP_RECENT=100`, the node downloads the closest available snapshot and replays all intermediate checkpoints. In the analyzed case, there were 247 checkpoints (~15.808 ledgers).

### Are buckets and checkpoints the same thing?
No. Buckets are complete snapshots of the state (large files, ~785 MB the largest). Checkpoints are transaction logs of 64 ledgers (small files, slow to apply because each transaction must be reprocessed in SQLite).

### Where does smart contract data reside?
The raw data lives in the Core/Captive Core buckets (PERSISTENT_CONTRACT_DATA, CONTRACT_CODE, TTL). Horizon extracts selected metadata into PostgreSQL tables such as `contract_asset_balances`, `contract_asset_stats`, and `asset_contracts`.

### Why are there two stellar-cores?
The Core Node (port 11626) participates in SCP/P2P consensus. The Captive Core (port 11726) is managed by Horizon solely to provide ledger metadata via pipe, without participating in consensus. This isolates data ingestion from the consensus process.
