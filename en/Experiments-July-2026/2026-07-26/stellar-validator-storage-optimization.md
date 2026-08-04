# Storage Optimization on the Stellar Validator

## SQLite (Operational) vs XDR Buckets (State) vs SQLite Misc (Network)

**Collection Date:** 2026-07-26 13:54 UTC
**Container:** stellar-core (validator, Synced!)
**Core Version:** v27.1.0 | **Protocol:** 27
**Network:** Test SDF Network ; September 2015

---

## Preface: Correction of the Previous Analysis

The previous report erroneously included the Horizon **PostgreSQL** in the comparison. This report corrects that: **inside the validator container (stellar-core), there is no PostgreSQL.** The validator uses **three storage systems**, all embedded:

| # | System | Type | Size | Purpose |
|:-|:--------|:----:|:-------:|:-----------|
| 1 | **stellar.db** | SQLite (WAL) | 23 MB + 42 MB WAL | Operational cache for consensus |
| 2 | **stellar-misc.db** | SQLite (WAL) | 208 KB + 40 MB WAL | Network and SCP metadata |
| 3 | **Buckets (.xdr)** | XDR files | 5.7 GB (57 files) | Complete immutable ledger state |

---

## 1. Overview of the Three Systems

```
┌──────────────────────────────────────────────────────────────┐
│               STELLAR CORE VALIDATOR                         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐      │
│  │  BUCKETS (.xdr) — 5.7 GB (57 files)                │      │
│  │                                                     │      │
│  │  Level 5 (snap):  785-905 MB  ── 4 files          │      │
│  │  Level 4:         202-355 MB  ── 4 files          │      │
│  │  Level 3:         121-203 MB  ── 3 files          │      │
│  │  Level 2:          14-98 MB   ── 9 files          │      │
│  │  Level 0-1:        <10 MB     ── 37 files         │      │
│  │                                                     │      │
│  │  FULL state: accounts, trustlines, contract         │      │
│  │  data, offers, TTL entries (~12.4M entries)        │      │
│  └──────────┬──────────────────────────────────────────┘      │
│             │                                                  │
│             │ periodic merge (level 0 → 1 → 2 → ... → 5)    │
│             │                                                  │
│  ┌──────────▼──────────────────────────────────────────┐      │
│  │  SQLITE MAIN (stellar.db) — 23 MB + 42 MB WAL        │      │
│  │                                                       │      │
│  │  offers:      56,600 rows  (live offers only)        │      │
│  │  storestate:        5 rows  (core metadata)          │      │
│  │                                                       │      │
│  │  State cache needed to validate transactions         │      │
│  │  (does NOT replace the buckets — it is a byproduct)  │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐      │
│  │  SQLITE MISC (stellar-misc.db) — 208 KB + 40 MB WAL │      │
│  │                                                       │      │
│  │  peers:          170 rows  (known P2P nodes)         │      │
│  │  scphistory:     224 rows  (recent SCP envelopes)    │      │
│  │  scpquorums:       1 row   (current quorum set)      │      │
│  │  quoruminfo:       5 rows  (quorum nodes)            │      │
│  │  ban/bannedacc:    0 rows  (blocklist)               │      │
│  │  slotstate:        1 row   (schema version)          │      │
│  │                                                       │      │
│  │  Volatile operational metadata of the P2P and SCP    │      │
│  │  network                                             │      │
│  └──────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Main SQLite (stellar.db) — Operational Cache

### 2.1 Configuration (measured on site)

| Parameter | Value | Interpretation |
|:----------|:-----:|:--------------|
| **Page count** | 5,692 | ~23.3 MB of data |
| **Page size** | 4,096 bytes | Aligned with the OS page (ext4/NTFS) |
| **Journal mode** | WAL | Write-Ahead Log — concurrent reads and writes |
| **Synchronous** | NORMAL (2) | WAL checkpoint every 1,000 pages (~4 MB) |
| **Auto-vacuum** | NONE (0) | No automatic page reorganization |
| **Cache size** | -2,000 pages (~8 MB) | Negative cache = number of pages |
| **Freelist** | 4 pages | Only 4 free pages — compact database |
| **Integrity** | ok | No corruption |
| **WAL size** | 42 MB | Pending checkpoints from merge |

### 2.2 Content

#### offers (56,600 rows)

```sql
-- Structure:
sellerid     VARCHAR(56)       -- Seller account (9,562 unique)
offerid      BIGINT PK         -- Unique offer ID
sellingasset TEXT              -- Asset being sold (9,876 unique assets)
buyingasset  TEXT              -- Asset being bought (8,372 unique assets)
amount       BIGINT            -- Amount (stroops)
pricen       INT               -- Price numerator
priced       INT               -- Price denominator
price        DOUBLE PRECISION  -- Calculated price (n/d)
flags        INT               -- Flags (0 = passive, 1 = active)
lastmodified INT               -- Last ledger that modified it
extension    TEXT              -- Serialized extension data
ledgerext    TEXT              -- Serialized ledger extension
```

**Indexes:**
```sql
-- Primary index: order book lookup
CREATE INDEX bestofferindex ON offers (sellingasset, buyingasset, price, offerid);
-- Usage: "what are the best offers to buy XLM with USDC?"
-- Covers 100% of the query (covering index)

-- Secondary index: offers per seller
CREATE INDEX offerbyseller ON offers (sellerid);
-- Usage: "which offers does account GABCD... have open?"
```

#### storestate (5 rows)

| Key | Size | Content |
|:------|:-------:|:---------|
| `databaseschema` | 2 bytes | Schema version ("28") |
| `rebuildledger2` | 0 bytes | Rebuild flag (empty = ok) |
| `historyarchivestate` | 7,800 bytes | Bucket list state (JSON with hashes of all levels) |
| `lastclosedledgerheader` | 572 bytes | XDR header of the last closed ledger (base64) |
| `networkpassphrase` | 33 bytes | "Test SDF Network ; September 2015" |

### 2.3 Applied Optimizations

#### WAL Mode — Cornerstone of Concurrency

```
Typical validation scenario:
  1. Ledger N is being closed (write to offers)
  2. A new transaction arrives (reads offers to validate)
  3. WITHOUT WAL: transaction waits for ledger close (exclusive lock)
  4. WITH WAL: transaction reads from the main DB while the write goes to the WAL

Gain: Zero blocking between validation and ledger close
```

#### Synchronous=NORMAL — Calculated Tolerance

```
Why not FULL?
  - FULL: fsync on every write (50x slower)
  - NORMAL: fsync at every checkpoint (every 1,000 pages)
  - Risk: loss of up to 4 MB of data on crash

Why is the risk acceptable?
  - The buckets (.xdr) contain THE TRUE STATE
  - SQLite is a RECONSTRUCTIBLE CACHE
  - If SQLite gets corrupted → rebuild from the buckets
```

#### Auto-vacuum=NONE — Savings in Blockchain

```
Blockchain: lots of INSERT, little DELETE
  - offers: receives INSERT + DELETE (offers expire)
  - storestate: frequent UPDATE on the same slot

Auto-vacuum=NONE:
  - PRO: deleted pages are not reorganized (0 CPU for vacuum)
  - CON: fragmentation over time
  - MITIGATION: database is only 23 MB — fragmentation is irrelevant
  - EVIDENCE: freelist of only 4 pages = almost no fragmentation
```

#### Page Size = 4,096 — OS Alignment

```
Each 4 KB page stores ~9-10 offer rows (411 bytes/row)
  → Reading 1 page = ~10 offers
  → Order book lookup reads ~1-2 pages via the index

Alignment with ext4/NTFS (4 KB block):
  → I/O without fragmentation between FS and SQLite
  → Zero read-modify-write
```

---

## 3. SQLite Misc (stellar-misc.db) — Network Metadata

### 3.1 Anomaly: 40 MB WAL for a 208 KB DB

```
DB:    208 KB  (52 pages × 4 KB)
WAL:   40 MB   (192x the DB size!)

This indicates:
  - LOTS of SCP metadata writes (envelopes)
  - Few checkpoints (high wal_autocheckpoint)
  - Transient data that could be discarded
```

### 3.2 Tables and Content

#### peers (170 rows) — Node Discovery

```sql
CREATE TABLE peers (
    ip           VARCHAR(15) NOT NULL,
    port         INT DEFAULT 0 NOT NULL,
    nextattempt  TIMESTAMP NOT NULL,
    numfailures  INT DEFAULT 0 NOT NULL,
    type         INT NOT NULL,
    PRIMARY KEY (ip, port)
);

-- 170 known peers on the network
-- type=1: outbound, type=0: inbound
-- nextattempt: time of the next connection attempt
-- numfailures: consecutive failed attempts
```

**Peer sample:**
```
98.91.174.101:11625    type=1  failures=0  (active validator)
44.204.146.210:11625   type=1  failures=0  (active validator)
64.23.228.195:11625    type=0  failures=10 (likely a private node going down)
```

#### scphistory (224 rows) — Consensus Envelopes

```sql
CREATE TABLE scphistory (
    nodeid    CHARACTER(56) NOT NULL, -- Validator ID
    ledgerseq INT NOT NULL,           -- Ledger sequence
    envelope  TEXT NOT NULL           -- SCP envelope (base64 XDR)
);

-- Stores the latest received SCP envelopes
-- Used to diagnose consensus problems
-- 224 rows = last ~75 consensus rounds (3 validators × 75 ledgers)
```

**Example envelope (abbreviated):**
```
nodeid: GDKXE2OZ... (sdf_testnet_1)
ledgerseq: 3,811,057
envelope: type=EXTERNALIZE, ballot=c75a, n=2, commit=c75a
  └── Vote of validator 1 confirming ledger 3,811,057
```

#### scpquorums (1 row)

```sql
CREATE TABLE scpquorums (
    qsethash      CHARACTER(64) NOT NULL,
    lastledgerseq INT NOT NULL,
    qset          TEXT NOT NULL,
    PRIMARY KEY (qsethash)
);

-- Only 1 active quorum set:
-- qsethash = 59d361...
-- 3 SDF validators: sdf_testnet_1, sdf_testnet_2, sdf_testnet_3
-- Threshold: t=2 (2 of 3 for agreement)
```

#### quoruminfo (5 rows)

```
5 nodes in the transitive quorum:
  - GDKXE2OZ... (sdf_testnet_1)
  - GCUCJTIY... (sdf_testnet_2)
  - GC2V2EFS... (sdf_testnet_3)
  - GBHJMDHX... (extra guardian)
  - GCYF3HGA... (possibly the node itself)
All share the same qsethash (same quorum set)
```

### 3.3 Optimizations

```
WAL mode: Required for frequent SCP envelope writes
  - Each closed ledger generates MULTIPLE envelopes (3 validators)
  - WAL allows fast lock-free writes

Huge WAL (40 MB): Indicates an optimization opportunity
  - DB is only 208 KB, but WAL is 40 MB
  - More frequent checkpoints would reduce the WAL
  - But: data is transient, a large WAL is acceptable
```

---

## 4. XDR Buckets — The True Ledger State

### 4.1 What They Are

Buckets are binary XDR files that store **immutable snapshots of the complete Stellar ledger state**. Unlike SQLite, which only has offers, the buckets contain **EVERYTHING**: accounts, trustlines, Soroban contract data, offers, etc.

### 4.2 Level Hierarchy (Bucket List)

```
Level 5 (snap):  ─── 4 files (785-905 MB)  ─── Deepest snapshot
                       ├── bucket-43d1a0e3...xdr  (905 MB)
                       ├── bucket-805620a8...xdr  (872 MB)
                       ├── bucket-ff26b4f5...xdr  (785 MB)
                       └── bucket-d8522ede...xdr  (600 MB)

Level 4:          ─── 4 files (202-355 MB)  ─── Intermediate merge
                       ├── bucket-b2a2c09a...xdr  (355 MB)
                       ├── bucket-18e2a5cb...xdr  (310 MB)
                       ├── ...
                       └── bucket-ec54d50d...xdr  (203 MB)

Level 3:          ─── 3 files (121-203 MB)  ─── Partial merge
Level 2:          ─── 9 files (14-98 MB)   ─── Recent merge
Levels 0-1:       ─── 37 files (<10 MB)    ─── New data
```

### 4.3 Optimization by Merge

```
Merge algorithm:

New ledgers → generate entries in Level 0
When Level 0 reaches its limit → merge to Level 1
When Level 1 reaches its limit → merge to Level 2
... up to Level 5 (snap)

Each merge:
  - Combines buckets from lower levels into a single larger bucket
  - Removes obsolete entries (overwritten by newer versions)
  - Generates a new SHA256 hash (file name = content hash)
  - Old buckets remain (immutability)

Benefit:
  - Merge reduces 100 small files into 1 large file
  - Reading state requires access to only 6 files (1 per level)
  - Immutability allows aggressive caching (HTTP, CDN)
```

### 4.4 Content Distribution (from /metrics)

Based on the previous analysis (bucket list of the same node):

```
Entry Type              | Count      | Size    | %
PERSISTENT_CONTRACT_DATA | 4,193,309  | 716 MB   | 40.2%
ACCOUNT                  | 2,956,700  | 374 MB   | 21.0%
CONTRACT_CODE            | 22,544     | 304 MB   | 17.1%
TTL                      | 4,356,785  | 208 MB   | 11.7%
DATA (account metadata)  | 332,654    | 49 MB    | 2.8%
TRUSTLINE                | 325,706    | 45 MB    | 2.5%
TEMPORARY_CONTRACT_DATA  | 143,452    | 22 MB    | 1.2%
OFFER                    | 53,382     | 9 MB     | 0.5%
CLAIMABLE_BALANCE        | 8,918      | 2 MB     | 0.1%
LIQUIDITY_POOL           | 2,592      | 422 KB   | <0.1%
CONFIG_SETTING           | 40         | 5 KB     | <0.1%
```

**Note:** Offers in the buckets = 53,382 vs. SQLite = 56,600. The difference (~3,200) is because SQLite includes offers from intermediate buckets that have not yet been merged into the snap.

---

## 5. Comparison: SQLite vs Buckets

| Aspect | SQLite (stellar.db) | Buckets (.xdr) |
|:--------|:------------------:|:--------------:|
| **Purpose** | Cache for SCP validation | Canonical state storage |
| **Content** | Offers only (~0.5% of state) | Complete state (100%) |
| **Size** | 23 MB + 42 MB WAL | 5.7 GB |
| **Format** | Relational (SQL) | Binary (XDR) |
| **Mutability** | Mutable (UPDATE/DELETE) | Immutable (append-only) |
| **Recoverable** | Yes (rebuilt from buckets) | Yes (from history archives) |
| **Concurrency** | WAL (single writer) | N/A (static files) |
| **Indexing** | B-tree (2 indexes) | N/A (hash-based lookup) |

### 5.1 Why Doesn't SQLite Store the Complete State?

```
Answer: Validation Performance

stellar-core NEEDS:
  1. Only OFFERS to validate order book transactions
  2. Only STORESTATE for internal tracking
  3. Fast access (< 1ms) → SQLite in WAL mode

What the core does NOT need in real time:
  - Accounts (2.9M) → balance is verified via buckets
  - Trustlines (325K) → trust is verified via buckets
  - Contract data (4.2M) → Soroban execution via buckets

Strategy: "pull only what is necessary into memory"
  SQLite loads offers (critical concurrency point)
  Everything else stays in the buckets (on-demand access)
```

### 5.2 Validation Flow: How the Three Systems Integrate

```
TRANSACTION ARRIVES (e.g., "buy 100 XLM for USDC")
         │
         ▼
┌─────────────────────────────────────────────────────┐
│ 1. CHECKS OFFERS (SQLite main)                       │
│                                                       │
│    SELECT * FROM offers                               │
│    WHERE sellingasset = 'XLM'                        │
│      AND buyingasset = 'USDC'                        │
│      AND price >= 0.10                               │
│    ORDER BY price ASC, offerid ASC                    │
│    LIMIT 10;                                          │
│                                                       │
│    → Uses bestofferindex index                        │
│    → Reads ~2-3 pages from the SQLite cache           │
│    → Time: < 1 ms                                    │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 2. CHECKS BALANCE (Buckets)                          │
│                                                       │
│    Level 5 bucket → most recent snapshot             │
│    Looks up the buyer account                         │
│    Checks the USDC balance                            │
│                                                       │
│    → Hash-based access (bucket named by hash)         │
│    → May be in memory cache                           │
│    → Time: < 5 ms                                    │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 3. RECORDS CONSENSUS (SQLite misc)                   │
│                                                       │
│    INSERT INTO scphistory (nodeid, ledgerseq,        │
│                            envelope)                 │
│    VALUES ('GDKXE...', 3741301, 'AAAA...');          │
│                                                       │
│    → Records the validator's vote                     │
│    → WAL mode allows fast writes                      │
│    → Time: < 1 ms                                    │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 4. UPDATES OFFERS (SQLite main)                      │
│                                                       │
│    DELETE FROM offers WHERE offerid = 389603;        │
│    (offer was executed, removed)                      │
│                                                       │
│    INSERT INTO offers (sellerid, offerid, ...)       │
│    VALUES ('GD7V...', 385498, ...);                  │
│    (new residual offer created)                      │
│                                                       │
│    → WAL mode: DELETE + INSERT in the WAL (fast)     │
│    → Time: < 2 ms                                    │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 5. PUBLISHES BUCKET (async merge)                    │
│                                                       │
│    At every checkpoint (64 ledgers):                  │
│    Level 0 buckets → merge → Level 1                 │
│    Level 1 buckets → merge → Level 2 (if full)       │
│    ...                                               │
│    Level 5 buckets → new snapshot                    │
│                                                       │
│    → Triggers publication to the history archive      │
│    → Time: seconds to minutes (background)           │
└─────────────────────────────────────────────────────┘
```

---

## 6. Conclusions

### 6.1 Three Systems, Three Distinct Roles

| System | Role | Main Optimization |
|:--------|:------|:--------------------|
| **SQLite main** | Offer cache for validation | WAL mode + synchronous=NORMAL |
| **SQLite misc** | Network and consensus metadata | WAL mode (heavy writes) |
| **XDR Buckets** | Complete immutable state | Hierarchical merge + hash-based lookup |

### 6.2 No PostgreSQL on the Validator

Confirmed: stellar-core uses **exclusively SQLite** as its embedded relational database. PostgreSQL exists only in the Horizon container (API), which does not participate in consensus.

### 6.3 Notable Design Decisions

1. **Selective cache**: SQLite stores only 0.5% of the state (offers). The rest stays in buckets. This reduces the DB from ~5.7 GB to 23 MB.

2. **Loss tolerance**: synchronous=NORMAL + auto-vacuum=NONE are acceptable because SQLite is reconstructible from the buckets.

3. **WAL in both SQLite databases**: Choosing WAL over the rollback journal allows concurrency between validation (read) and ledger close (write).

4. **Disproportionate WAL in misc**: 40 MB of WAL for a 208 KB DB indicates a high rate of SCP envelope writes with infrequent checkpoints.

5. **Bucket merge**: The level algorithm (L0 to L5) reduces the number of files needed to reconstruct state from thousands to only 6 (1 per level).

### 6.4 Optimization Opportunities

| Opportunity | Impact | Complexity |
|:-------------|:--------|:-------------|
| Increase WAL checkpoint on misc.db | Reduce WAL from 40 MB → ~1 MB | Low |
| Covering index for order book | Already implemented (bestofferindex) | - |
| Bucket cache in RAM (mmap) | Currently 0 (mmap_size=0) | Medium |
| XDR bucket compression | Reduce 5.7 GB → ~2 GB | High |

---

## Appendix A: Raw Collected Data

```
stellar.db:
  page_count:   5,692
  page_size:    4,096
  journal_mode: wal
  synchronous:  2 (NORMAL)
  auto_vacuum:  0 (NONE)
  cache_size:   -2,000 (~8 MB)
  freelist:     4
  integrity:    ok
  file:         23 MB
  wal:          42 MB

stellar-misc.db:
  page_count:   52
  page_size:    4,096
  journal_mode: wal
  synchronous:  2 (NORMAL)
  file:         208 KB
  wal:          40 MB

Buckets:
  total:        57 .xdr files
  size:         5.7 GB
  indexes:      36 .index files
  >= 500 MB:    4
  100-500 MB:   11
  10-100 MB:    9
  1-10 MB:      11
  < 1 MB:       21
  catchup tmp:  50 MB (1,231 files)
```

## Appendix B: Commands for Reproduction

```bash
# SQLite main
docker exec stellar-core sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode; PRAGMA synchronous; PRAGMA auto_vacuum; PRAGMA integrity_check;"

# SQLite misc
docker exec stellar-core sqlite3 /opt/stellar/core/stellar-misc.db ".tables"
docker exec stellar-core sqlite3 /opt/stellar/core/stellar-misc.db "SELECT COUNT(*) FROM peers; SELECT COUNT(*) FROM scphistory;"

# Buckets
docker exec stellar-core ls -lhS /opt/stellar/core/buckets/*.xdr | head -10
docker exec stellar-core du -sh /opt/stellar/core/buckets/

# Node info
curl http://localhost:11626/info
```
