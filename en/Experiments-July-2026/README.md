# Experiments — July 2026 (English Version)

This folder is the **English version** of the July 2026 experiments. The original Portuguese files are in `pt/Experimentos-Julho-2026/`.

The experiments focus on operating and analyzing a **Stellar Testnet node (stellar-core + Horizon)** running in Docker: initial synchronization, ledger/mempool monitoring, transaction flows, container architecture changes (splitting Core + Horizon), and storage optimization.

## Overview

| Date / Folder | Topic |
|---|---|
| [`2026-07-15/`](2026-07-15/) | Initial setup and synchronization of the Stellar node |
| [`2026-07-16/`](2026-07-16/) | Ledger/mempool monitoring (30, 100 and 500 ledgers) + transaction flow |
| [`2026-07-17/`](2026-07-17/) | Node synchronization and catch-up analysis |
| [`2026-07-20/`](2026-07-20/) | Complete synchronization and node state report |
| [`2026-07-21/`](2026-07-21/) | Implementation plan: split into Core + Horizon containers, SQL analysis |
| [`2026-07-26/`](2026-07-26/) | Storage optimization on the Stellar validator |
| [`Docker-Core-Horizon-Separated/`](Docker-Core-Horizon-Separated/) | Docker setup: stellar-core and stellar-horizon as separate containers |
| [`Docker-MainNet/`](Docker-MainNet/) | Docker setup: Core + Horizon on MainNet |
| [`Docker-MainNet-CoreOnly/`](Docker-MainNet-CoreOnly/) | Docker setup: stellar-core only on MainNet |
| [`Docker-Stellar/`](Docker-Stellar/) | Original single-container setup (stellar/quickstart) + Mermaid diagrams |

---

## `2026-07-15/` — Initial Synchronization

- **`REPORT.md`** — Complete report of the first Stellar Testnet run in Docker: architecture (single container with supervisord), ~14 min initial synchronization, bucket list (~10 GB of ~11 GB total), RAM/storage consumption (~6 GB RAM).
- **`Day-Report.md`** — Summary of the day's activities, files generated and observations.
- **`FULL-REPORT.pdf`** — PDF version of the complete report (1.27 MB, 9 pages), generated via Puppeteer.

## `2026-07-16/` — Monitoring and Transactions

- **`Day-Report.md`** — Summary of the day's monitoring activities.
- **`Submitted-Transaction-Local-Horizon-Report.md`** — Complete flow of a transaction submitted through the local Horizon API: from XDR signing to ledger inclusion, with SQL/history evidence.

### `Monitoring-30-ledgers/` (30 ledgers, ~150 s)
- **`mempool-report.md`** — Mempool and transaction throughput analysis: success/failure rates, TxSet vs. executed operations, fee pool evolution, memory consumption.
- **`chart-ledgers.html`** — Interactive Chart.js charts of the monitoring data (open in a browser).
- **`ledger-data.json` / `ledger-data.csv`** — Raw monitoring data (ledger-by-ledger).
- **`categorized-failures.json`** — Failures decoded/categorized by type.

### `Monitoring-100-ledgers/` (100 ledgers)
- **`REPORT.md`** — Monitoring report.
- **`chart-ledgers-100.html`** — Interactive charts.
- **`data-100-ledgers.json`** — Raw data.

### `Monitoring-500-ledgers/` (500 ledgers, ~42 min)
- **`REPORT.md`** — Monitoring report.
- **`chart-ledgers-500.html`** — Interactive charts (horizontal scroll, 158 KB).
- **`chart-ledgers-500-split.html`** — Same charts split into 5 groups.
- **`data-500-ledgers.json`** — Raw data (309.7 KB).

## `2026-07-17/` — Synchronization and Catch-up

- **`stellar-synchronization-analysis.md`** — Detailed analysis of how the node synchronizes: discovery, history archive download, bucket list state, catch-up metrics, SQLite vs PostgreSQL roles.
- **`Node-Up-Synchronization-Report.md`** — Report of the node catch-up process after being brought up.

## `2026-07-20/` — Complete Synchronization Report

- **`Complete-Stellar-Synchronization-Report.md`** — Full report on synchronization and node state: ledger headers, history archives, bucket hashes, insert rates during catch-up (up to 194 inserts/s on `history_operation_participants`).

## `2026-07-21/` — Architecture Change and SQL Analysis

- **`00-IMPLEMENTATION-PLAN.md`** — Implementation plan to split the single `stellar/quickstart:testing` container into two independent containers (stellar-core + stellar-horizon), with problems of the current model, ports, volumes and proposed architecture.
- **`dual-container-catching-up-report.md`** — Test report of the split (Core + Horizon as separate containers).
- **`node-synchronization-report.md`** — The synchronization process of a Stellar node (generic explanation).
- **`SQL-Transactions-90s-Analysis.md`** — Analysis of SQL transactions in the Stellar databases during 90 seconds of monitoring (INSERT-heavy pattern on history tables).

## `2026-07-26/` — Storage Optimization

- **`stellar-validator-storage-optimization.md`** — Study of storage optimization on the validator: SQLite (operational) vs XDR buckets (state) vs SQLite misc (network), WAL analysis, merge levels, optimization opportunities.
- **`analyze_dbs.sh`** — Shell script to analyze the Stellar databases.
- **`core_storage_analysis.sh`** — Shell script for complete storage analysis of the core validator.

## `Docker-Core-Horizon-Separated/` — Core + Horizon as Separate Containers

Result of the implementation plan from 2026-07-21: two independent containers on a bridge network.

- **`docker-compose.yml`** — Compose file: `stellar-core` (ports 11625/11626) + `stellar-horizon` (port 8000, PostgreSQL 5432) with healthchecks and volumes.
- **`README.md`** — Setup documentation.
- **`stellar-core/`** — `Dockerfile`, `entrypoint.sh`, `stellar-core.cfg` (validator config).
- **`stellar-horizon/`** — `Dockerfile`, `entrypoint.sh`, `horizon.env`, `nginx.conf`, `stellar-captive-core.cfg` (captive core config).
- **`monitor_all_sql.sh`, `monitor_sqlite_core.sh`, `sqlite_core_mon.sh`, `sqlite_captive_mon.sh`, `sql_monitor.sql`** — Monitoring scripts (SQL queries, SQLite stats, WAL).
- **`core-full-log.txt`, `core-last-log.txt`, `horizon-full-log.txt`** — Container execution logs (raw evidence).

## `Docker-MainNet/` — Core + Horizon on MainNet

Same architecture as above, but connected to the **Stellar MainNet** (network `Public Global Stellar Network ; September 2015`), used for storage studies of the bucket list model.

- **`docker-compose.yml`** + **`README.md`** — Setup and documentation.
- **`stellar-core/`** and **`stellar-horizon/`** — Dockerfiles, entrypoints and configs for MainNet.

## `Docker-MainNet-CoreOnly/` — Core Only on MainNet

Only stellar-core (no Horizon), to study storage and consensus participation on MainNet with reduced resource usage.

- **`docker-compose.yml`** + **`README.md`** — Setup and documentation.
- **`mainnet-storage-report.md`** — Storage report of the MainNet Core node (bucket list, SQLite, Soroban impact, MainNet vs TestNet comparison).
- **`stellar-core/`** — Dockerfile, entrypoint and config for MainNet Core-only.

## `Docker-Stellar/` — Original Setup + Diagrams

- **`docker-compose.yml`** — Original single-container setup (`stellar/quickstart:testing`).
- **`diagrams/`** — Mermaid diagrams of the architecture:
  - `01-databases.mmd` → ER diagram of the databases (PostgreSQL Horizon + SQLite Core/Captive + bucket list)
  - `02-tables.mmd` → Mindmap of the 33 PostgreSQL tables
  - `03-services.mmd` → Containers/services managed by supervisord
  - `04-synchronization.mmd` → Synchronization flow (discovery, state download, catch-up)
  - `05-bucket-list.mmd` → Bucket list hierarchy (11 levels, merges)
  - `06-connections.mmd` → Network connections between components
  - `png/` — Compiled PNG versions of each diagram
  - `package.json` — Mermaid-CLI dependency to compile the diagrams
