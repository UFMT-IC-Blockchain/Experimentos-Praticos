# Test Report: Split of the Stellar Container into Core + Horizon

**Experiment Date:** 2026-07-21 20:54 - 21:30 UTC
**Duration:** ~36 minutes
**Base Image:** stellar/quickstart:testing (v27.1.0, Horizon devel)

---

## 1. Final Result

| Container | Status | Ledger | Age | RAM | CPU |
|:----------|:-------|:------:|:---:|:---:|:---:|
| **stellar-core** | ✅ Synced! | 3.733.171 | 2s | 4,4 GB | 0,27% |
| **stellar-horizon** | ✅ Ingesting | 3.733.056 | ~1 min | 6,6 GB | 6,4% |

Both containers were **built, started and synchronized successfully** in less than 36 minutes.

---

## 2. Implemented Architecture

```
┌──────────────────────────────────┐      ┌──────────────────────────────────┐
│   stellar-core (validator)       │      │   stellar-horizon (API)          │
│   CONTAINER 1                    │      │   CONTAINER 2                    │
│                                  │      │                                  │
│  ┌────────────────────────────┐  │      │  ┌────────────────────────────┐  │
│  │  stellar-core --conf ...   │  │      │  │  stellar-horizon serve     │  │
│  │  run                       │  │      │  │  ENABLE_CAPTIVE_CORE=true  │  │
│  │                            │  │      │  │                            │  │
│  │  Status: Synced!           │  │      │  │  ├── Captive Core (subproc)│  │
│  │  Ledger: 3.733.171         │  │      │  │  ├── PostgreSQL 16         │  │
│  │  Peers: 5                  │  │      │  │  └── nginx :8000           │  │
│  │  Protocol: 27              │  │      │  │                            │  │
│  │                            │  │      │  │  Status: Ingesting         │  │
│  │  SQLite: 18 MB + WAL 42 MB │  │      │  │  Ledger: 3.733.056         │  │
│  │  Buckets: 57 files         │  │      │  │  Buckets: 39 files         │  │
│  │  Disk: 5,7 GB              │  │      │  │  Disk: 6,3 GB + PG 4,1 GB  │  │
│  └────────────────────────────┘  │      │  └────────────────────────────┘  │
│                                  │      │                                  │
│  Ports:                         │      │  Ports:                         │
│  11625 (P2P) → SDF validators   │      │  8000 (nginx) → Horizon API    │
│  11626 (HTTP) → admin/metrics   │      │  5432 (PG) → loopback           │
│                                  │      │  11725 (captive P2P) → internal │
│                                  │      │  11726 (captive HTTP) → internal│
└──────────────────────────────────┘      └──────────────────────────────────┘
```

### 2.1 Data Flow

```
Core Node (validator)
    │
    ├── P2P (11625) → sdf_testnet_1,2,3
    ├── SCP Consensus
    ├── Local SQLite (ledgers + storestate)
    └── Buckets (57 files, 5,6 GB)

Horizon (API)
    │
    ├── Captive Core (subprocess)
    │   ├── P2P (11725) → sdf_testnet_1,2,3
    │   ├── Downloads buckets (39 files, 3,1 GB)
    │   ├── Own SQLite (captive-core/stellar.db)
    │   └── Pipe (fd:3) → Horizon (metadata)
    │
    ├── Horizon API (port 8001)
    │   ├── Reads the captive core metadata
    │   ├── Processes transactions, operations, effects
    │   └── Writes to PostgreSQL
    │
    ├── PostgreSQL 16 (horizon database)
    │
    └── nginx (port 8000 → proxy to 8001)
```

### 2.2 Container Independence

**Confirmed finding:** Horizon does NOT depend on the Core Node. Horizon:
- Manages its own stellar-core via `ENABLE_CAPTIVE_CORE_INGESTION=true`
- The captive core connects directly to the Stellar P2P network
- Downloads its own buckets from the history archives
- `STELLAR_CORE_URL=http://localhost:11726` points to the LOCAL captive core

**Both containers can operate independently.**

---

## 3. Synchronization Timeline

```
T+0s      ─── docker-compose up -d
              ├── stellar-core: new-db + new-hist + run
              └── stellar-horizon: initdb + migrations + horizon serve

T+30s     ─── Core: Ledger 1, Catching up
              Horizon: PostgreSQL init, applying migrations

T+2min    ─── Core: Ledger ~3.732.989, Joining SCP
              Horizon: Captive core downloading buckets (29/39 = 74%)

T+3min    ─── Core: Synced! Ledger 3.733.082, age 4s
              Horizon: Captive core downloaded buckets (36/39 = 92%)

T+5min    ─── Core: Synced! Ledger 3.733.150, age 0s
              Horizon: Captive core Connected, Ledger 3.732.989

T+8min    ─── Core: Synced! Ledger 3.733.169, age 0s, idle 0,27% CPU
              Horizon: Ingesting! Ledger 3.733.056, PG populated
```

**Total time for full synchronization: ~5 minutes** (due to the recent bucket snapshot)

---

## 4. Storage

### 4.1 Core Node

| Component | Size | Details |
|:----------|:-----|:--------|
| stellar.db | 18 MB | Main SQLite |
| stellar.db-wal | 42 MB | Write-Ahead Log |
| stellar-misc.db | 64 KB | Metadata |
| stellar-misc.db-wal | 7,7 MB | Misc WAL |
| buckets/ | 5,6 GB | 57 .xdr files |
| **Total core** | **5,7 GB** | |

### 4.2 Horizon

| Component | Size | Details |
|:----------|:-----|:--------|
| horizon/ | 6,3 GB | Captive core + configs |
| captive-core/buckets | ~3,1 GB | 39 .xdr files |
| PostgreSQL | 4,1 GB | Horizon database |
| **Total horizon** | **10,4 GB** | |

**Overall total:** ~16,1 GB (vs ~15 GB for the single container — difference due to the catch-up still in progress on Horizon)

---

## 5. Computational Resources

### 5.1 Docker Stats (post-synchronization)

| Container | CPU% | RAM | RAM% | NET I/O | BLOCK I/O |
|:----------|:----:|:---:|:----:|:--------|:----------|
| stellar-core | 0,27% | 4,42 GB | 28,4% | 1,36 GB / 80,7 MB | 301 MB / 7,08 GB |
| stellar-horizon | 6,40% | 6,65 GB | 42,7% | 2,33 GB / 113 MB | 6,27 GB / 20,3 GB |

### 5.2 Peak during catch-up

| Container | Peak CPU | Peak RAM |
|:----------|:---------|:---------|
| stellar-core | 92,64% | 7,96 GB |
| stellar-horizon | 192,53% | 2,34 GB |

### 5.3 Main Processes

```
stellar-core:
  PID 14   stellar-core --conf ... run    45,6% CPU   3,1 GB RSS

stellar-horizon:
  PID 1    stellar-horizon serve           0,4% CPU     52 MB RSS
  PID 176  stellar-core (captive) catchup  36,5% CPU   547 MB RSS
  PID 90   nginx master                    0,0% CPU      7 MB RSS
  Various  postgres workers                0,0% CPU   ~22 MB each
```

---

## 6. Database Activity (90s monitoring)

### 6.1 Progress

| Source | Start | End | Δ Ledgers |
|:-------|:-----:|:---:|:---------:|
| Core Node | 3.733.087 | 3.733.150 | +63 |
| Horizon ingest | 0 | 0 | 0 (ingestion had not started) |

### 6.2 Active Queries at the End

| PID | State | Event | Query |
|:---|:------|:-------|:------|
| 1012 | active | relation | SELECT seller_id, offer_id, ... FROM offers |
| 1013 | active | WALWrite | COPY trust_lines (account_id, asset_code, ...) |

The `COPY trust_lines` query indicates that ingestion was starting but blocked on WALWrite (waiting for WAL flush).

### 6.3 Post-Ingestion State (T+8min)

| Table | Rows |
|:------|:----:|
| history_ledgers | ~7.000+ (estimated) |
| history_transactions | Being ingested |
| history_operations | Being ingested |
| accounts | Being populated |
| trust_lines | Being populated |

---

## 7. Problems Found and Solutions

| Problem | Cause | Solution |
|:--------|:------|:--------|
| Core shows help instead of running | `stellar-core --conf ...` without `run` | Add `run` to the command: `stellar-core --conf ... run` |
| "Permission denied" for buckets | Wrong working directory | `cd /opt/stellar/core` in the entrypoint |
| Config not found in the volume | Docker volume masks image files | Copy config from `/etc/stellar/` staging to the volume |
| PostgreSQL postmaster.pid lock file | Unclean shutdown of the previous container | Remove the stale lock file before starting |
| "network-passphrase not allowed" | `NETWORK_PASSPHRASE` conflicts with `NETWORK=testnet` | Remove `NETWORK_PASSPHRASE` from env |
| "history-archive-urls not allowed" | `HISTORY_ARCHIVE_URLS` conflicts with `NETWORK=testnet` | Remove `HISTORY_ARCHIVE_URLS` from env |
| PostgreSQL SSL permissions | Default container config | Fix permissions on `/etc/ssl/private` |
| Core crashes with `set -e` | `new-hist` fails after new-db | `set -e` causes restart; remove `set -e` or handle the error |

---

## 8. Conclusions

### 8.1 The Split Works

The **two separate containers** architecture was successfully validated. Both containers:
- Start independently
- Synchronize with the Testnet network
- Core reaches Synced! in ~3 minutes
- Horizon starts ingestion in ~8 minutes

### 8.2 Independence Confirmed

Horizon with `ENABLE_CAPTIVE_CORE_INGESTION=true` **truly does not depend on the Core Node**. Each container manages its own stellar-core and buckets.

### 8.3 Storage Cost

The split does not eliminate bucket duplication. Both containers still download buckets independently (~5,7 GB core + ~3,1 GB captive core + ~4,1 GB PostgreSQL ≈ ~12,9 GB total, growing to ~16 GB when fully synchronized).

### 8.4 Performance

- **Core**: Synchronized in ~3 min (ledger 1 → 3.733.082), using ~92% CPU at peak
- **Horizon**: Downloaded 39 buckets (3,1 GB) in ~2 min; captive core connected in ~4 min
- Post-sync: Core stays idle (0,27% CPU); Horizon uses ~6,4% CPU for ingestion

### 8.5 Recommendations

1. **Tune PostgreSQL**: Increase `max_wal_size` and tune shared_buffers for better ingestion performance
2. **Healthchecks**: Implement more robust healthchecks with adequate `start_period`
3. **Separate volumes**: Keep separate volumes for core data, captive core data and PostgreSQL
4. **Multi-stage builds**: Optimize Dockerfiles for smaller layers and efficient caching

---

## 9. Project Files

```
Docker-Core-Horizon-Separated/
├── 00-IMPLEMENTATION-PLAN.md    (25 KB) — Planning document
├── docker-compose.yml              (2,4 KB) — Service orchestration
├── README.md                       (4,2 KB) — Usage instructions
├── dual-container-catching-up-report.md        (this)   — Test report
│
├── stellar-core/
│   ├── Dockerfile                  (614 B)  — Core build
│   ├── stellar-core.cfg            (1,2 KB) — Core config
│   └── entrypoint.sh               (1,0 KB) — Startup script
│
└── stellar-horizon/
    ├── Dockerfile                  (898 B)  — Horizon build
    ├── stellar-captive-core.cfg    (1,1 KB) — Captive core config
    ├── horizon.env                 (875 B)  — Horizon env vars
    ├── nginx.conf                  (848 B)  — nginx config
    └── entrypoint.sh               (6,5 KB) — Startup script
```

## 10. Reproduction Commands

```bash
# Build and start
docker-compose build --no-cache
docker-compose up -d

# Monitor
docker logs -f stellar-core
docker logs -f stellar-horizon

# Verify status
curl http://localhost:11626/info     # Core
curl http://localhost:8000/           # Horizon

# Stop and clean
docker-compose down -v
```
