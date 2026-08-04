# Activity Report — 15/07/2026

**Course:** Master's Degree — Blockchain  
**Experiment Objective:** Execution, monitoring and analysis of a complete Docker container of the Stellar Testnet with Horizon, aiming to understand the service architecture, storage, synchronization and connectivity of the Stellar network in a controlled environment.

---

## 1. Activities Performed

### 1.1 Verification and Inspection of the Running Container

The `stellar-testnet` container (image `stellar/quickstart:testing`) had been running since the previous day (14/07/2026). The following inspections were performed:

- **Container identification:** `docker ps` confirmed the active container with ID `4fbe5ce9b7cd`, internal IP `172.18.0.2`, persistent volume `stellar-data` mounted at `/opt/stellar`.
- **Supervisord (PID 1):** It was confirmed that Supervisor managed all child processes. The managed services were identified with their respective priorities and autostart policies.
- **Stellar Core Node (PID 291):** Active consensus node, consuming approximately 2.8 GB of RAM (~17.6% of the container), connected to the testnet network via P2P port 11625. Its full configuration was extracted from the `/opt/stellar/core/etc/stellar-core.cfg` file, revealing parameters such as `CATCHUP_RECENT=100`, `UNSAFE_QUORUM=true`, `FAILURE_SAFETY=1`, and the list of three SDF validators (sdf_testnet_1, sdf_testnet_2, sdf_testnet_3).
- **Captive Core (PID 3985):** Horizon's subprocess responsible for data ingestion, consuming ~2.9 GB of RAM (~17.9%). Running in `--console run --metadata-output-stream fd:3` mode, with P2P port 11725 and HTTP port 11726 (localhost). A detailed comparative study between Node and Captive Core was documented, highlighting differences in consensus participation, lifecycle, execution mode and bucket list management.
- **Horizon API (PID 349):** REST server consuming ~182 MB of RAM, operating on internal port 8001 and exposed via Nginx on port 8000. Its environment variables were fully captured, including `DATABASE_URL`, `STELLAR_CORE_URL`, `ENABLE_CAPTIVE_CORE_INGESTION=true` and `INGEST=true`.
- **PostgreSQL (PID 330):** Database version 14 (Alpine) with ~25 MB of RAM in the main process, port 5432, `horizon` database with 33 tables totaling ~1.2 GB.
- **Nginx (PID 288/289):** Reverse proxy operating on port 8000, forwarding requests to Horizon on port 8001.

### 1.2 Mapping the Directory Structure

A complete exploration of the container's directory tree at `/opt/stellar/` was performed, documenting the directory hierarchy of each service:

- **Core:** Directories `bin/`, `etc/`, `buckets/` (bucket list), in addition to the SQLite databases `stellar.db` (~18 MB) and `stellar-misc.db` (~22 MB).
- **Horizon:** Directories `bin/`, `etc/`, `captive-core/` containing `stellar.db` (~21 MB), `stellar-misc.db` (~14 MB) and isolated buckets (~5.4 GB).
- **PostgreSQL:** Directories `data/` (~1.2 GB), `etc/` with `postgresql.conf`, `pg_hba.conf` and `pg_ident.conf`.
- **Nginx and Supervisor:** Configuration directories in `nginx/etc/` and `supervisor/etc/`.

### 1.3 Capture of Network Connections

All active network connections of the container were captured and documented:

- **P2P ESTABLISHED connections (port 11625):** Nine peers identified, including IPs such as `13.223.55.158`, `44.204.146.210`, `3.85.105.105`, among others.
- **SYN-SENT connections (in progress):** Four connection attempts to additional peers.
- **Captive Core connection:** One peer connected on port 11725 (`18.220.162.149`).
- **SDF validators:** Three official validators mapped with names, public keys and addresses (`core-testnet1/2/3.stellar.org`).
- **History Archives:** Three `history.stellar.org` endpoints used for state and buckets download.

### 1.4 Analysis of the Databases

A detailed analysis of all databases involved in the architecture was performed:

- **PostgreSQL (Horizon):** `horizon` database with 33 tables, totaling ~1.2 GB. The largest tables identified were `accounts` (497 MB), `accounts_signers` (428 MB), `trust_lines` (107 MB) and `accounts_data` (94 MB). History tables such as `history_transactions` (10 MB) and `history_operations` (3.3 MB) were also documented, in addition to auxiliary and join tables.
- **SQLite (Node Core):** `stellar.db` (~18 MB, with WAL ~62 MB) storing consensus metadata; `stellar-misc.db` (~22 MB with WAL) for miscellaneous data.
- **SQLite (Captive Core):** `captive-core/stellar.db` (~21 MB, with WAL ~33 MB); `captive-core/stellar-misc.db` (~14 MB with WAL).

### 1.5 Bucket List Study

The bucket list — Stellar Core's immutable, merge-based state storage mechanism — was analyzed in depth:

- **Structure:** 11 hierarchical levels (0 to 10), where each level contains buckets representing state snapshots at different time scales.
- **Sizes:** From ~25 KB (level 0) up to ~822 MB (level 10), with a periodic merge every 64 ledgers.
- **Directories:** The complete `buckets/` structure was documented, including the `history/`, `meta-debug/`, `publishqueue/` and `tmp/` subdirectories.
- **Bucket List (Node):** ~4.7 GB at `/opt/stellar/core/buckets/`.
- **Bucket List (Captive):** ~5.4 GB at `/opt/stellar/horizon/captive-core/captive-core/buckets/`.
- **Catchup Process:** The 8-step flow was documented, from determining the trigger ledger to full synchronization and participation in SCP consensus.

### 1.6 Documentation of the Initialization Process (Startup)

The `/start` entrypoint script (~600 lines of bash) was analyzed in its 7 phases:

1. **process_args:** Definition of network variables (`NETWORK_PASSPHRASE`, `HISTORY_ARCHIVE_URLS`).
2. **copy_defaults:** Copy of default configurations to the service directories.
3. **init_db:** PostgreSQL initialization with database and user creation.
4. **init_stellar_core:** SQLite schema creation and stellar-core configuration.
5. **init_horizon:** Creation of the 33 tables in PostgreSQL via `horizon db init`.
6. **exec_supervisor:** Supervisor initialization with priorities and autostart policies.
7. **Monitoring:** Status checking loops and sequential initialization of the optional services.

The real synchronization timeline was recorded, totaling approximately 14 minutes from container initialization to complete Horizon ingestion (ledger ~3,629,501).

### 1.7 Mermaid Diagram Generation

Six Mermaid diagrams were created to graphically represent the system's architecture and flows:

1. **Databases Diagram (ER):** Entity-relationship mapping among PostgreSQL (Horizon), SQLite (Node and Captive Core) and Bucket Lists, with sizes and main tables.
2. **Tables Diagram (Mindmap):** Organization of the 33 PostgreSQL tables into four categories: Current State, History, Auxiliary and Join Tables.
3. **Services Diagram:** Hierarchical architecture of the services managed by Supervisor, with details on PIDs, memory consumption, ports and dependency relationships.
4. **Synchronization Diagram (Sequence):** Complete synchronization flow in 5 phases — Discovery, State Download, Checkpoints, Horizon Ingestion and Continuous Operation.
5. **Bucket List Hierarchy:** Representation of the 11 levels with sizes, merge process and connection to History Archives.
6. **Network Connections Diagram:** Mapping of all external connections with SDF validators, P2P peers, History Archives and the local user.

Each diagram was generated in two formats: Mermaid source code (`.mmd`) and compiled PNG image, stored in `Docker-Stellar/diagrams/`.

### 1.8 Report Preparation

The following documents were produced:

- **REPORT.md:** Unified main document, containing all sections — machine specifications, general architecture, initialization process, container services, network connections, databases, bucket list, synchronization flow, diagrams and conclusion. It includes both the Mermaid source code and the compiled PNG images.
- **FULL-REPORT.pdf:** PDF version of the report, generated via Puppeteer with professional A4 formatting, including headers, footers with page numbering and all rendered diagrams.
- **Day-Report.md:** The present document, consolidating the day's activities in academic language.

### 1.9 Repository Configuration

- **.gitignore:** Added and fixed the exclusion of the `node_modules` directory in `Experiments-July-2026/Docker-Stellar/diagrams/`.
- **Version control:** All files were versioned in the Git repository `UFMT-IC-Blockchain/Experimentos-Praticos` (branch `main`), with properly documented commits.

---

## 2. Final Structure of the Generated Files

```
Experiments-July-2026/
└── 2026-07-15/
    ├── REPORT.md                     # Complete report (1043 lines)
    ├── FULL-REPORT.pdf           # PDF version (1.27 MB, 9 pages)
    └── Day-Report.md                 # Present document
└── Docker-Stellar/
    ├── docker-compose.yml               # Docker Compose configuration
    └── diagrams/
        ├── 01-databases.mmd                # Mermaid code — Databases ER Diagram
        ├── 02-tables.mmd               # Mermaid code — Tables Mindmap
        ├── 03-services.mmd              # Mermaid code — Container Services
        ├── 04-synchronization.mmd         # Mermaid code — Synchronization Flow
        ├── 05-bucket-list.mmd            # Mermaid code — Bucket List Hierarchy
        ├── 06-connections.mmd              # Mermaid code — Network Connections
        ├── package.json                 # Mermaid-CLI dependency
        ├── package-lock.json
        └── png/
            ├── 01-databases.png            # Compiled diagram (93 KB)
            ├── 02-tables.png           # Compiled diagram (104 KB)
            ├── 03-services.png          # Compiled diagram (63 KB)
            ├── 04-synchronization.png     # Compiled diagram (149 KB)
            ├── 05-bucket-list.png        # Compiled diagram (93 KB)
            └── 06-connections.png          # Compiled diagram (106 KB)
```

---

## 3. Observations and Results

- The `stellar/quickstart:testing` container consumes approximately **6 GB of RAM** and **~10-11 GB of storage** in the Docker volume, demonstrating the operational complexity of a complete Stellar Testnet node.
- The two-instance Stellar Core architecture (Node + Captive) proved effective in separating the consensus and data ingestion responsibilities, allowing Horizon to operate without interfering with the main node.
- The initial synchronization time of ~14 minutes highlights the optimization provided by the use of History Archives and pre-computed buckets.
- The bucket list, with its 11 hierarchical levels and periodic merge process, constitutes the main storage bottleneck, representing ~10 GB of the ~11 GB total.

---

> **Report generated on:** 15/07/2026  
> **Container:** stellar/quickstart:testing (testnet)  
> **Ledger at collection time:** ~3,629,501
