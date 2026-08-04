# Synchronization Report: Analysis of the Stellar Node Catch-up Process

**Date:** 2026-07-18
**Network:** Stellar Testnet ("Test SDF Network ; September 2015")
**Container:** stellar-testnet (stellar/quickstart:testing)
**Core Version:** v27.1.0
**Final State:** Synced! (Ledger 3.663.823)

---

## 1. Introduction

This report documents the **initial synchronization (catch-up)** process of a Stellar Core node when connecting to the Testnet. The goal is to explain the internal state recovery mechanisms, clarify the relationship between buckets and checkpoints, and justify the observed duration of the process.

---

## 2. Storage Architecture

Stellar Core organizes the network's historical data into two complementary structures: **buckets** (state snapshots) and **checkpoints** (transaction logs).

### 2.1 Buckets (Snapshots)

Buckets are binary XDR files that contain the **complete state** of the network at a given point in time. They store accounts, trustlines, offers, Soroban contract data, etc. — all the state required to rebuild the ledger without reprocessing historical transactions.

```
Size of the 5 largest buckets downloaded by the node:

bucket-ff26b4f5...7efd.xdr   785 MB   │████████████████████████████████████████
bucket-eb7625ce...4b72.xdr   610 MB   │███████████████████████████████
bucket-d8522ede...2d730.xdr   600 MB   │██████████████████████████████
bucket-8a27deda...b125.xdr   452 MB   │█████████████████████████
bucket-b2a2c09a...d09b.xdr   355 MB   │███████████████████
                                    ──┴────────────────────
                                    Total buckets: 4,4 GB
```

Buckets are organized into **merge levels** (0 to 6). Low-level buckets are small and frequent; high-level buckets (snap) are large and represent the consolidated state.

```
Bucket Merge Levels:

Level 0 (base):  ~677 buckets    ██▌ (small, recent data)
Level 1:         ~2.797 buckets  ███████████▌
Level 2:         ~758 buckets    ███▌
Level 3:         ~208 buckets    █▌
Level 4:         ~63 buckets     ▎
Level 5:         ~18 buckets     ▏
Level 6 (snap):  ~4 buckets      ▏ (785 MB the largest)
```

### 2.2 Checkpoints (Transaction Logs)

Checkpoints are files that contain the **raw transactions** of 64 consecutive ledgers (~5 minutes of network activity). Unlike buckets, checkpoints do not contain the final state — only the operations that modify the state.

```
Checkpoint structure:

 Ledger 1 ─┬─ Transaction A (payment)
           ├─ Transaction B (create_account)
           ├─ Transaction C (set_options)
           └─ Transaction D (soroban_invoke)
 
 Ledger 2 ─┬─ Transaction E (manage_offer)
           ├─ ...
           ...
 
 ... up to 64 ledgers (~620 transactions per checkpoint)
```

## 3. The CATCHUP_RECENT Mechanism

### 3.1 Definition

The `CATCHUP_RECENT=100` directive in the `stellar-core.cfg` file determines the node's **recovery strategy**:

> "Download a bucket snapshot that covers at least N ledgers back, then replay the remaining checkpoints."

### 3.2 How It Works

```
Snapshot selection process:

Network timeline:

Genesis  ─────┬──────┬──────┬──────┬──────┬──────┬──────► Now (ledger 3.663.823)
              │      │      │      │      │      │
Buckets available in the SDF archives:
              │      │      │      │      │      │
              ▼      ▼      ▼      ▼      ▼      ▼
              B1     B2     B3     B4     B5     B6
                                              ▲
                                              │
                                    Chosen bucket snapshot
                                    (most recent covering
                                     ≥ 100 ledgers back)
```

Stellar Core searches the history archive for the **most recent available bucket snapshot** that corresponds to a checkpoint at least `CATCHUP_RECENT` ledgers away from the target ledger. In the concrete case:

```
Chosen bucket snapshot:
  Creation date: 07/16/2026 ~01:00 UTC
  Approximate ledger: 3.647.615

Target ledger (start): 3.663.423
Difference: 15.808 ledgers = 247 checkpoints (of 64 each)
```

The value `100` in `CATCHUP_RECENT=100` does not mean "100 checkpoints" — it means "at least 100 ledgers of margin". Because snapshots are sparse, the actual margin was **15.808 ledgers**.

### 3.3 Trade-off

```
High CATCHUP_RECENT (e.g., 1000000):
  ├─ Downloads MOST RECENT bucket     (less data, fast download)
  └─ MORE checkpoints to replay       (more CPU/SQLite time)

Low CATCHUP_RECENT (e.g., 100):
  ├─ Downloads OLDER bucket           (more data, slow download)
  └─ FEWER checkpoints to replay      (less CPU/SQLite time)
```

| Strategy | Download | Replay | Total Time |
|:---------|:---------|:-------|:-----------|
| Recent snapshot + long replay | Fast (1 bucket) | Slow (247 checkpoints) | **Hours** |
| Old snapshot + short replay | Slow (many buckets) | Fast (few checkpoints) | **Variable** |
| No CATCHUP_RECENT (full replay) | None | Very slow (3,6M ledgers) | **Days** |

## 4. Observed Synchronization Cycle

### 4.1 Timeline

```
00:22:42  ─── Container start (stellar-core node)
                │
                ▼
       ┌─────────────────────┐
       │  Bucket download    │
       │  (4,4 GB)           │ ←──── Only ~30 seconds
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │  Apply buckets      │
       │  (SHA verification) │ ←──── State rebuilt up to ledger ~3.647.615
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │  Download & apply   │
       │  checkpoints        │ ←─────── 247 checkpoints to reprocess
       │  (247 = 15.808 led.)│
       └─────────┬───────────┘
                 │
          ┌──────┴──────┐
          ▼              ▼
    ┌──────────┐  ┌──────────┐
    │ 38% done │  │ 65% done │
    │ (151/247)│  │ (86/247) │
    └──────────┘  └──────────┘
          │              │
          ▼              ▼
    ┌──────────┐  ┌──────────┐  ←──── The network keeps producing
    │ 89% done │  │ 88% done │       new ledgers (1 every 5s)
    │ (24/247) │  │ (26/247) │       while the replay runs
    └──────────┘  └──────────┘
          │              │
          ▼              ▼
    ~20:40h  ──── Synced! (ledger 3.663.823)
```

### 4.2 Percentage Oscillation

During catch-up, the progress percentage was observed to **oscillate** even while checkpoints were being processed:

```
Example log:         Checkpoints left   % done
                     151                (39%)
                     150                (39%)   ← same %!
                     149                (39%)   ← same %!
                     148                (40%)   ↑ went up only 1%
```

**Explanation:** The percentage is calculated as:

```
% = (total_remaining - total_initial) / total_current
```

Where `total_current` grows continuously because the network produces ~1 ledger every 5 seconds. While the node processes old checkpoints, **new checkpoints are added to the denominator** — progress "chases a moving target".

```
Moving target visualization:

  Network current ledger ─────►████████████████████████████████████████████████
                                      ↑
                                     Moving target (goes up ~1 ledger/5s)
 
  Node ledger ──────────►███████████
                                ↑
                        Node processing checkpoints
 
  Gap: the smaller the gap, the higher the %
  Because the target moves up, the % can stagnate even while the node advances
```

### 4.3 Relative Position Node vs Horizon

The container runs **two independent stellar-core processes**, each downloading its own buckets and checkpoints:

```
Node (port 11626)       ──► ledger 3.663.423 (catch-up)
   │
   │ Gap of ~2.100 ledgers
   │ (started 3,5 min earlier)
   ▼
Horizon Captive Core     ──► ledger 3.663.487 (catch-up)
(port 11726)
   │
   │ Gap of ~6 ledgers
   │ (processing latency)
   ▼
Horizon (ingest)         ──► ledger 3.663.481 (ingestion into PostgreSQL)
```

## 5. Replay Performance Analysis

### 5.1 Why is the replay slow?

Each checkpoint of 64 ledgers requires:

1. **Download** of the XDR file from the history archive (~ network)
2. **Deserialization** of the XDR into in-memory structures
3. **Reapplication** of ~620 transactions into SQLite (sequential writes)
4. **Soroban contract execution** (CPU intensive — 261 billion instructions)
5. **SHA256 hash verification** of each operation
6. **Bucket merge** at the lower levels

### 5.2 Load Profile (core node metrics)

| Metric | Value |
|:-------|:------|
| Ledgers applied successfully | 39.129 |
| Ledgers with failures | 7.742 |
| Transactions applied | 46.871 |
| Operations applied | 71.502 |
| Avg transactions/ledger | ~9,7 |
| Avg operations/ledger | ~15,0 |
| Soroban calls (host functions) | 31.194 |
| CPU instructions (Soroban) | ~261 billion |

### 5.3 State Distribution in Buckets

The Testnet state is dominated by Soroban smart contracts, which makes the replay more expensive:

```
State composition (1,84 GB uncompressed):

PERSISTENT_CONTRACT_DATA  40,2%  ██████████████████████████████████████
ACCOUNT                   20,3%  ██████████████████▌
CONTRACT_CODE             17,7%  █████████████████
TTL                       11,8%  ██████████▌
TRUSTLINE                  2,5%  ██▌
DATA                       2,7%  ██▌
OFFER                      0,5%  ▌
OTHERS (8 categories)      4,3%  ███▌
                                      ──┴────
                                      Total: 100%
```

**Observation:** Soroban contracts (PERSISTENT_CONTRACT_DATA + CONTRACT_CODE + TTL) account for ~70% of the state. Each Soroban transaction requires WASM compilation, execution of host functions, and metadata verification — significantly more expensive than a simple payment transaction.

### 5.4 SQLite State During Catch-up

```
File                    Size       Function
stellar.db              21 MB      Main database (ledgers)
stellar.db-wal          44 MB      Write-Ahead Log (intense writes)
stellar.db-shm          96 KB      Shared Memory
stellar-misc.db         208 KB     Miscellaneous metadata
stellar-misc.db-wal     40 MB      Metadata WAL
```

The 44 MB WAL (Write-Ahead Log) indicates **intense, continuous writing** — SQLite is under constant load during the checkpoint replay.

## 6. Total Storage

```
Total storage in /opt/stellar/: ~15 GB

core/          4,6 GB  │███████████████████████████████▌
  ├── buckets/ 4,4 GB │██████████████████████████████
  └── stellar  21 MB  │▏

horizon/       4,7 GB  │████████████████████████████████
  ├── captive- 4,6 GB │██████████████████████████████▌
  └── stellar  21 MB  │▏

postgresql/    5,3 GB  │████████████████████████████████████▎
  ├── accounts 873 MB │██████
  ├── signers  1,4 GB │██████████▏
  ├── txs      679 MB │█████
  └── others   2,3 GB │███████████████▋

lab/           171 MB  │█▎
others         116 KB  │▏
```

**Bucket duplication:** The Core Node and the Horizon Captive Core maintain independent buckets (~4,4 GB each = ~8,8 GB duplicated). This is intentional — Horizon uses captive core to isolate ingestion from consensus.

## 7. Conclusions

1. **The bottleneck is not download, it's replay.** The buckets (4,4 GB) were downloaded in seconds; the 247 checkpoints (~15.808 ledgers) took hours to reprocess in SQLite.

2. **CATCHUP_RECENT=100 does not mean "100 checkpoints".** The value defines a minimum margin in ledgers. Due to the sparsity of snapshots in the archives, the actual margin was ~15.808 ledgers.

3. **The percentage oscillates because the target is moving.** New ledgers are produced by the network during catch-up, making the denominator of the progress calculation grow continuously.

4. **Soroban makes the replay slower.** Smart contracts represent ~70% of the Testnet state, and each Soroban transaction requires WASM compilation + execution of host functions, increasing the CPU cost per checkpoint.

5. **The bucket duplication between Core Node and Captive Core (~8,8 GB) is the price of isolation** between the consensus process and the Horizon data ingestion process.

---

## References

- Stellar Core Documentation: https://developers.stellar.org/docs/data/history
- Stellar Bucket System: https://github.com/stellar/stellar-core/blob/master/docs/software/ledger.md
- Analyzed node configuration: `/opt/stellar/core/etc/stellar-core.cfg`
- Synchronization logs: `/var/log/stellar-core/`
- Raw data collected on 2026-07-18 via `curl http://localhost:11626/info` and `curl http://localhost:11626/metrics`
