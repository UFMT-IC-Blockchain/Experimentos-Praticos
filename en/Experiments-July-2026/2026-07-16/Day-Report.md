# Activity Report — 07/16/2026

**Course:** Master's Degree — Blockchain  
**Experiment Objective:** Systematic monitoring of the mempool, transaction throughput, and Stellar Testnet network behavior across three time scales (30, 100, and 500 ledgers), with failure decoding via XDR and generation of analytical reports with interactive charts.

---

## 1. Activities Performed

### 1.1 Experiment 1: 30-Ledger Monitoring (Mempool and Throughput)

**Time:** ~9:32 PM BRT  
**Ledgers:** L#3646628 to L#3646657 (~150 seconds)

The first systematic mempool monitoring was performed, collecting data via the Horizon API (`localhost:8000`) and the Stellar Core HTTP API (`localhost:11626`). The data was processed and stored in JSON and CSV, with failure categorization via XDR decoding.

**Metrics collected per ledger:**
- OK and FAIL transactions
- Operations executed and proposed in the TxSet
- Accumulated fee pool
- Process memory consumption

**Main results:**
- **236 OK**, **42 FAIL** — success rate of **84.9%**
- Average throughput: **1.57 tx/s**
- TxSet utilization: **6.8%** (low — no congestion)
- Fee pool: **+0.4524 XLM** (linear growth)
- Total container RAM: **~6.91 GiB** (44.4% of 15.56 GiB)

**Categorized failures (4 types):** PAYMENT_NOTRUST (dominant), PAYMENT_NODESTINATION, PAYMENT_UNDERFUNDED, SOROBAN_TRAPPED, txFeeBumpInnerFailed.

**Files generated:** `Monitoring-30-ledgers/` — `chart-ledgers.html`, `ledger-data.json`, `ledger-data.csv`, `categorized-failures.json`, `mempool-report.md`.

### 1.2 Documentation of the Transaction Flow (Submitted-Transaction-Local-Horizon)

A detailed report was produced documenting the complete lifecycle of a transaction submitted via a local client (`@stellar/stellar-sdk`) through to persistence in PostgreSQL. The tracked transaction was a payment of **99 XLM** (ledger 3646201), spanning 9 steps:

1. Construction and signing in the Node.js client
2. Submission to Horizon (`POST /transactions`)
3. Validation by Captive Core (sequence, signature, balance, time bounds)
4. Propagation to the P2P network (port 11725)
5. SCP consensus (4 phases with 3/3 SDF validators)
6. Ledger closure (11 OK + 2 FAIL)
7. Metadata return via pipe (fd:3)
8. Persistence in the PostgreSQL (3 history tables + accounts)
9. HTTP 200 confirmation with ResultXDR

**Document generated:** `Submitted-Transaction-Local-Horizon-Report.md`

### 1.3 Experiment 2: 100 Ledger Monitoring

**Time:** ~10:10-10:23 PM BRT  
**Ledgers:** L#3647282 to L#3647381 (~8 minutes)

Automated collection of the same indicators as Experiment 1, but at an extended scale. Data was grouped into **10 groups of 10 ledgers** for trend analysis.

**Results:**
- **765 OK**, **171 FAIL** — success rate of **81.7%**
- Average of **7.7 OK** and **1.7 FAIL**/ledger
- Fee pool: **+6.2009 XLM** (linear growth)
- Backlog: maximum of **504 ops**

**Categorized failures (7 types):** PAYMENT_NOTRUST 61%, PAYMENT_NODESTINATION 16%, PAYMENT_UNDERFUNDED 11%, SOROBAN_TRAPPED 8%, DECODE_ERR 2%, OP_TOOMANYSUBENTRIES 1%, OP_CREATEACCOUNT 1%.

**Files generated:** `Monitoring-100-ledgers/` — `chart-ledgers-100.html`, `data-100-ledgers.json`, `REPORT.md`.

### 1.4 Experiment 3: 500 Ledger Monitoring

**Time:** ~10:10-10:23 PM BRT  
**Ledgers:** L#3646525 to L#3647024 (~42 minutes)

Extended monitoring for long-term behavior analysis, especially backlog accumulation and the evolution of failure rates. Data was grouped into **17 groups of ~30 ledgers**.

**Results:**
- **4,173 OK**, **839 FAIL** — success rate of **83.3%**
- Average of **8.35 OK** and **1.68 FAIL** per ledger
- Throughput: **1.67 tx/s**
- Backlog: **2,829 ops** (continuous growth — input > processing)
- Fee pool: **+15.9239 XLM**

**Categorized failures (9 types):** PAYMENT_NOTRUST 61%, PAYMENT_NODESTINATION 16%, PAYMENT_UNDERFUNDED 10%, DECODE_ERR 5%, SOROBAN_TRAPPED 5%, OP_TYPE_REVOKESPONSORSHIP 2%, OP_TYPE_MANAGESELLOFFER 1%, OP_TOOMANYSUBENTRIES 0.5%, OP_TYPE_CHANGETRUST 0.2%.

**Critical finding:** The backlog grew from **5 to 2,829 ops** during the period, indicating that the transaction generation rate consistently exceeded the testnet's processing capacity.

**Files generated:** `Monitoring-500-ledgers/` — `chart-ledgers-500.html`, `chart-ledgers-500-split.html`, `data-500-ledgers.json`, `REPORT.md`.

### 1.5 Generation of Interactive Charts (Chart.js)

For each experiment, HTML files with **7 interactive charts** were generated using Chart.js:

1. **OK vs FAIL** — stacked bars per ledger
2. **TxSet vs Executed** — comparative bars
3. **Success Rate (%)** — line with area
4. **Fee Pool** — cumulative line
5. **Mempool Flow** — stacked bars (input, confirmed, rejected)
6. **Backlog** — 3 lines (proposed, processed, backlog)
7. **Failures by Type** — multiple lines per category

The charts for the 500-ledger experiment were generated in two versions: a single screen with horizontal scroll (15000px) and a version split into 5 groups of 100 ledgers.

### 1.6 Failure Decoding via XDR

All failed transactions were decoded using:
- `stellar-core print-xdr --base64` for decoding the `result_xdr` field
- The `xdr` module from the `@stellar/stellar-sdk` library for programmatic interpretation

Failure categories were extracted and tallied for each experiment, enabling the generation of distribution charts and comparative tables.

### 1.7 Report Preparation

The following documents were produced for each experiment:

- **REPORT.md** (100 and 500 ledgers): Complete reports with tables, grouped Mermaid charts, and detailed analyses
- **Submitted-Transaction-Local-Horizon-Report.md**: Documentation of the end-to-end transaction flow
- **mempool-report.md**: Mempool-focused analysis (30 ledgers)
- **This document (Day-Report.md)**: Academic consolidation of the day's activities

### 1.8 Version Control and Organization

- **Reorganization:** Files were moved from a single directory into subdirectories by monitoring type (`Monitoring-30-ledgers/`, `Monitoring-100-ledgers/`, `Monitoring-500-ledgers/`)
- **Commits made:**
  - `ce01edc` — Adds experiments from 07/16/2026 (initial files)
  - `12f26df` — Reorganizes into subdirectories by monitoring type
  - `c8cbc40` — Adds reports and updates charts

---

## 2. Final Structure of Generated Files

```
Experiments-July-2026/
└── 2026-07-16/
    ├── Day-Report.md                              # This document
    ├── Submitted-Transaction-Local-Horizon-Report.md # Transaction flow (11 KB)
    ├── Monitoring-30-ledgers/
    │   ├── mempool-report.md                      # Mempool analysis (7.6 KB)
    │   ├── chart-ledgers.html                        # Interactive charts (37 KB)
    │   ├── ledger-data.json                          # Raw data (9.1 KB)
    │   ├── ledger-data.csv                           # CSV data (1.2 KB)
    │   └── categorized-failures.json                 # Decoded failures (5.8 KB)
    ├── Monitoring-100-ledgers/
    │   ├── REPORT.md                              # Complete report (12.8 KB)
    │   ├── chart-ledgers-100.html                    # Interactive charts (16.3 KB)
    │   ├── data-100-ledgers.json                    # Raw data (54.4 KB)
    │   └── Day-Report.md                          # This document
    └── Monitoring-500-ledgers/
        ├── REPORT.md                              # Complete report (15.2 KB)
        ├── chart-ledgers-500.html                    # Horizontal scroll charts (158 KB)
        ├── chart-ledgers-500-split.html           # Charts in 5 groups (78.8 KB)
        ├── data-500-ledgers.json                    # Raw data (309.7 KB)
        └── Day-Report.md                          # This document
```

---

## 3. Observations and Results

- **Consistent success rate:** All experiments showed success rates between **81.7% and 84.9%**, indicating that this is the testnet's baseline under the experimental conditions.
- **PAYMENT_NOTRUST dominates failures:** ~61% in all experiments — suggests a systematic problem with trust line configuration on the test accounts.
- **Growing backlog:** The 500-ledger experiment revealed a backlog of **2,829 ops**, demonstrating that transaction generation exceeded the network's processing capacity throughout the entire period.
- **Underutilized mempool:** Despite the backlog, only **6.8%** of the TxSet capacity (200 ops/ledger) was utilized.
- **Linear fee pool:** No evidence of Surge Pricing — the base fees of 100 stroops were not altered.
- **Stable memory consumption:** The container maintained ~6.91 GiB of RAM (44.4%), with Node and Captive Core consuming ~2.8 GB each.

---

> **Report generated on:** 07/16/2026  
> **Image:** stellar/quickstart:testing (testnet)  
> **Experiments:** 30, 100, and 500 consecutive ledgers  
> **Total transactions analyzed:** ~5,400 transactions