# Implementation Plan: Split of the Stellar Container into Separate Core + Horizon

**Date:** 2026-07-21
**Base:** Current setup `stellar/quickstart:testing` (single container)
**Target:** Two independent containers: `stellar-core` (validator) + `stellar-horizon` (API)

---

## 1. Current Architecture Summary

```
SINGLE CONTAINER (stellar/quickstart:testing)
supervisord manages 5+ processes in the same container:

┌─────────────────────────────────────────────────────┐
│                    SINGLE CONTAINER                  │
│                                                      │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────┐ │
│  │ Core Node    │   │ Captive Core │   │ Horizon  │ │
│  │ (validator)  │   │ (child of    │   │ (API)    │ │
│  │ P2P + HTTP   │   │  Horizon)    │   │          │ │
│  │ SQLite+buckts│   │ SQLite+buckts│   │ PostgreSQL│ │
│  └──────┬───────┘   └──────┬───────┘   └────┬─────┘ │
│         │                  │                │        │
│   11625/11626         11725/11726         8001      │
│         │                  │                │        │
│         └──────────────────┴────────────────┘        │
│                    nginx (port 8000)                  │
└─────────────────────────────────────────────────────┘
```

### Issues with the current model:
1. **A single container manages everything** — if Core crashes, Horizon is affected too
2. **Shared resources** — CPU/RAM without isolation between processes
3. **Duplicated buckets** — Core Node + Captive Core download ~8,5 GB of the same data
4. **Mixed logs** — all services log to the same stdout
5. **Coupled restart** — it is not possible to update Core without restarting Horizon

---

## 2. Proposed Architecture

```
TWO INDEPENDENT CONTAINERS

┌──────────────────────────────┐      ┌──────────────────────────────────┐
│   CONTAINER 1: stellar-core  │      │   CONTAINER 2: stellar-horizon   │
│   (Validator / Consensus)    │      │   (API / Ingestion)              │
│                              │      │                                  │
│  ┌────────────────────────┐  │      │  ┌────────────────────────────┐  │
│  │   stellar-core         │  │      │  │   PostgreSQL (14)          │  │
│  │                        │  │      │  │   - database: horizon     │  │
│  │   - SCP Consensus      │  │      │  │   - port 5432             │  │
│  │   - P2P Network        │  │      │  └────────────────────────────┘  │
│  │   - SQLite (ledgers)   │  │      │             │                    │
│  │   - Buckets (4,3 GB)   │  │      │  ┌────────────────────────────┐  │
│  │                        │  │      │  │   stellar-horizon          │  │
│  │   Ports:               │  │      │  │                            │  │
│  │   11625 (P2P)          │  │      │  │   - REST API on port 8001  │  │
│  │   11626 (HTTP admin)   │  │      │  │   - Captive Core (internal)│  │
│  └────────────────────────┘  │      │  │   - Pipe fd:3 from captive │  │
│                              │      │  │   - PostgreSQL             │  │
│  Volumes:                    │      │  │                            │  │
│   - stellar-core-data:/opt   │      │  │   Ports:                   │  │
│                              │      │  │   8000 (nginx) → 8001     │  │
│                              │      │  │   11725 (captive P2P)     │  │
│                              │      │  │   11726 (captive HTTP)    │  │
│                              │      │  └────────────────────────────┘  │
│                              │      │                                  │
│                              │      │  Volumes:                        │
│                              │      │   - horizon-data:/opt/stellar   │
│                              │      │   - pgdata:/var/lib/postgresql  │
└──────────────────────────────┘      └──────────────────────────────────┘
         │                                       │
         │ (no direct dependency)                │
         │                                       │
         ▼                                       ▼
   P2P: sdf_testnet{1,2,3}              P2P: sdf_testnet{1,2,3}
   Archive: history.stellar.org         Archive: history.stellar.org
```

### Data Flow

```
Container 1 (Core):
  P2P (11625) → SCP consensus with SDF validators
  HTTP (11626) → Admin info, metrics, upgrades
  Buckets (4,3 GB) → Ledger state
  SQLite (21 MB) → Local metadata
  → Does NOT send data to Horizon

Container 2 (Horizon):
  Captive Core (internal, port 11726) → P2P with SDF validators
  Captive Core → Pipe (fd:3) → Horizon (ledger metadata)
  Horizon → PostgreSQL (processed data)
  nginx (8000) → proxy to Horizon (8001)
  → Does NOT depend on Container 1 for ingestion
```

---

## 3. Dependency Analysis

### 3.1 Does Horizon NEED the Core Node?

**Not for ingestion.** Horizon with `ENABLE_CAPTIVE_CORE_INGESTION=true`:
- Manages its own stellar-core process (captive core)
- The captive core connects directly to the Stellar P2P network
- The captive core downloads its own buckets from the history archives
- Horizon reads metadata via pipe from the captive core → does NOT use the core node HTTP

**STELLAR_CORE_URL** (used only for `transaction submission` when `INGEST=false`) → not applicable here.

**Conclusion:** The two containers are **independent** — they can run without communicating.

### 3.2 Advantages of the Split

| Aspect | Single Container | Separate Containers |
|:-------|:-----------------|:--------------------|
| **Failure isolation** | Core crashes → everything down | Core crashes → Horizon still serves the API |
| **Resources** | Shared CPU/RAM | Independent per-container limits |
| **Upgrades** | Must rebuild the entire image | Can upgrade Core or Horizon separately |
| **Logs** | Mixed in stdout | Logs separated per container |
| **Storage** | ~8,5 GB duplicated | ~8,5 GB duplicated (same) |
| **Complexity** | Simple (1 container) | More complex (orchestration) |

### 3.3 Disadvantages of the Split

| Aspect | Impact |
|:-------|:-------|
| **Duplicated buckets** | Stays the same (~8,5 GB total) |
| **Extra configuration** | Need to configure network, volumes, healthchecks |
| **Initial synchronization** | Both need to catch up independently |
| **Maintenance** | Two Docker images to manage |

---

## 4. Proposed Directory Structure

```
Docker-Core-Horizon-Separated/
│
├── 00-IMPLEMENTATION-PLAN.md     ← this file
│
├── stellar-core/                    ← Core Node container (validator)
│   ├── Dockerfile                   ← Docker image for Core
│   ├── stellar-core.cfg             ← Core configuration
│   ├── entrypoint.sh                ← Startup script
│   └── .dockerignore
│
├── stellar-horizon/                 ← Horizon container (API + ingestion)
│   ├── Dockerfile                   ← Docker image for Horizon
│   ├── stellar-captive-core.cfg     ← Captive core configuration
│   ├── horizon.env                  ← Horizon environment variables
│   ├── entrypoint.sh                ← Startup script
│   ├── nginx.conf                   ← nginx configuration
│   └── .dockerignore
│
├── docker-compose.yml               ← Orchestration of the two containers
├── .env                             ← Common variables (network, passphrase)
└── README.md                        ← Usage instructions
```

---

## 5. Network Configuration Between Containers

```
Docker network: stellar-network (bridge)

Container: stellar-core
  networks:
    stellar-network:
      ipv4_address: 172.20.0.10
  ports:
    - "11625:11625/tcp"   # P2P (exposed to the host)
    - "11626:11626/tcp"   # HTTP admin

Container: stellar-horizon
  networks:
    stellar-network:
      ipv4_address: 172.20.0.11
  ports:
    - "8000:8000/tcp"     # Public HTTP (nginx → Horizon)
    - "5432:5432/tcp"     # PostgreSQL (optional, debug)
  
  # Captive core uses internal ports (not exposed): 11725 (P2P), 11726 (HTTP)
```

### Exposed vs Internal Ports

| Service | Container | Internal Port | Exposed? | Use |
|:--------|:----------|:--------------|:---------|:----|
| Core P2P | stellar-core | 11625 | Yes | Consensus with validators |
| Core HTTP | stellar-core | 11626 | Yes | Admin/metrics |
| Captive P2P | stellar-horizon | 11725 | **No** | Internal only |
| Captive HTTP | stellar-horizon | 11726 | **No** | Internal only (loopback) |
| Horizon API | stellar-horizon | 8001 | No (nginx) | REST API |
| nginx public | stellar-horizon | 8000 | Yes | Proxy to Horizon |
| PostgreSQL | stellar-horizon | 5432 | Optional | Horizon database |

---

## 6. Volumes and Persistent Data

### Container 1: stellar-core

```yaml
volumes:
  - core-data:/opt/stellar/core    # SQLite + buckets + config
```

### Container 2: stellar-horizon

```yaml
volumes:
  - horizon-data:/opt/stellar/horizon    # Captive core data + config
  - pgdata:/var/lib/postgresql/14/main   # PostgreSQL data
```

### Estimated volume sizes

| Volume | Estimated Size | Content |
|:-------|:---------------|:--------|
| core-data | ~4,6 GB | SQLite (21 MB) + WAL (44 MB) + Buckets (4,3 GB) + indexes |
| horizon-data | ~4,7 GB | Captive SQLite (21 MB) + Buckets (4,3 GB) + configs |
| pgdata | ~5,3 GB | 33 tables, ~9,3M rows, WAL |
| **Total** | **~14,6 GB** | |

---

## 7. Dockerfiles

### 7.1 stellar-core/Dockerfile

```dockerfile
# Image based on stellar/quickstart:testing, extracting only the Core
FROM stellar/quickstart:testing AS base

# Stage 1: Only stellar-core
FROM ubuntu:22.04

# Install stellar-core (copied from the official image or installed via apt)
COPY --from=base /usr/bin/stellar-core /usr/bin/stellar-core
COPY --from=base /usr/lib/x86_64-linux-gnu/lib* /usr/lib/x86_64-linux-gnu/

# Configuration
COPY stellar-core.cfg /opt/stellar/core/etc/stellar-core.cfg
COPY entrypoint.sh /entrypoint.sh

RUN useradd -m -s /bin/bash stellar && \
    mkdir -p /opt/stellar/core /var/log/stellar-core && \
    chown -R stellar:stellar /opt/stellar/core /var/log/stellar-core && \
    chmod +x /entrypoint.sh

VOLUME ["/opt/stellar/core", "/var/log/stellar-core"]
EXPOSE 11625 11626

USER stellar
ENTRYPOINT ["/entrypoint.sh"]
CMD ["stellar-core", "--conf", "/opt/stellar/core/etc/stellar-core.cfg"]
```

### 7.2 stellar-horizon/Dockerfile

```dockerfile
FROM stellar/quickstart:testing AS base

FROM ubuntu:22.04

# Dependencies: PostgreSQL 14, nginx, stellar-core (for captive), stellar-horizon
RUN apt-get update && apt-get install -y \
    postgresql-14 \
    nginx \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Binaries
COPY --from=base /usr/bin/stellar-core /usr/bin/stellar-core
COPY --from=base /usr/bin/stellar-horizon /usr/bin/stellar-horizon
COPY --from=base /usr/lib/x86_64-linux-gnu/lib* /usr/lib/x86_64-linux-gnu/

# Configuration
COPY horizon.env /opt/stellar/horizon/etc/horizon.env
COPY stellar-captive-core.cfg /opt/stellar/horizon/etc/stellar-captive-core.cfg
COPY nginx.conf /etc/nginx/sites-available/default
COPY entrypoint.sh /entrypoint.sh

RUN useradd -m -s /bin/bash stellar && \
    mkdir -p /opt/stellar/horizon /var/run/postgresql && \
    chown -R stellar:stellar /opt/stellar/horizon && \
    chmod +x /entrypoint.sh

VOLUME ["/opt/stellar/horizon", "/var/lib/postgresql"]
EXPOSE 8000 5432

ENTRYPOINT ["/entrypoint.sh"]
```

---

## 8. Startup Sequence

### Container 1: stellar-core (simple)

```
1. entrypoint.sh
2. stellar-core new-db (first time)
3. stellar-core force-scp (if necessary)
4. stellar-core --conf stellar-core.cfg
5. Waits for P2P connection with validators
6. Catch-up: downloads buckets + checkpoints
7. Enters Synced! / SCP consensus mode
```

### Container 2: stellar-horizon (more complex)

```
1. entrypoint.sh
2. initdb PostgreSQL (first time)
3. start PostgreSQL
4. createdb horizon
5. horizon db init (migrations)
6. stop PostgreSQL
7. start PostgreSQL (final)
8. start nginx
9. start stellar-horizon
   ├── horizon starts the captive core as a subprocess
   │   └── stellar-core --conf stellar-captive-core.cfg
   └── captive core:
       ├── downloads buckets (~4,3 GB)
       ├── downloads checkpoints
       ├── replays transactions
       └── feeds Horizon via pipe fd:3
10. Horizon ingests metadata into PostgreSQL
11. API available on port 8000
```

### Dependencies Between Containers

```yaml
# docker-compose.yml
services:
  stellar-core:
    # ... no depends_on

  stellar-horizon:
    depends_on:
      stellar-core:
        condition: service_healthy
    # NOTE: Horizon does NOT depend on Core to operate,
    # but we can monitor Core as a status reference
```

**Note:** Horizon does NOT need Core to be running. The `depends_on` is optional and only serves as a startup order reference.

---

## 9. Healthchecks

### Core Node

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:11626/info"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 120s
```

### Horizon

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:8001/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 180s
```

---

## 10. Restart Policy

```yaml
stellar-core:
  restart: unless-stopped
  # If Core crashes, Docker restarts it automatically
  # Horizon keeps serving historical data

stellar-horizon:
  restart: unless-stopped
  # If Horizon crashes, it restarts independently of Core
```

---

## 11. Configuration Comparison

### Configuration that REMAINS THE SAME

| Item | Core | Horizon (captive) |
|:-----|:-----|:------------------|
| `NETWORK_PASSPHRASE` | `Test SDF Network ; September 2015` | `Test SDF Network ; September 2015` |
| `[[VALIDATORS]]` | sdf_testnet_1, 2, 3 | sdf_testnet_1, 2, 3 |
| `HISTORY_ARCHIVE_URLS` | `https://history.stellar.org/...` | `https://history.stellar.org/...` |
| `CATCHUP_RECENT` | 100 | N/A (captive core does not use it) |
| `UNSAFE_QUORUM` | true | true |
| `FAILURE_SAFETY` | 1 | 1 |
| `ENABLE_SOROBAN_DIAGNOSTIC_EVENTS` | false | false |

### Configuration that CHANGES

| Item | Before (single) | After (core) | After (horizon) |
|:-----|:----------------|:--------------|:-----------------|
| `HTTP_PORT` | 11626 (core) / 11726 (captive) | 11626 | 11726 |
| `PEER_PORT` | 11625 (core) / 11725 (captive) | 11625 | 11725 |
| `DATABASE` | sqlite3://...core/... (core) / sqlite3://...horizon/... (captive) | sqlite3://... | sqlite3://... (in the horizon container) |
| `DATABASE_URL` (Horizon env) | postgres://localhost/horizon | N/A | postgres://localhost/horizon (in the same container) |
| `STELLAR_CORE_URL` (Horizon env) | http://localhost:11726 | N/A | http://localhost:11726 (captive core in the same container) |
| `PUBLIC_HTTP_PORT` | true (core) / false (captive) | true | false |

---

## 12. Implementation Steps

### Phase 1: Preparation
- [ ] Create the directory structure
- [ ] Extract current configurations from the running container
- [ ] Identify exact binary versions (stellar-core v27.1.0, stellar-horizon)

### Phase 2: Core Container
- [ ] Create Dockerfile for stellar-core
- [ ] Copy stellar-core.cfg (adjust paths)
- [ ] Create entrypoint.sh (new-db, force-scp, init-hist)
- [ ] Test build and isolated execution

### Phase 3: Horizon Container
- [ ] Create Dockerfile for stellar-horizon + PostgreSQL
- [ ] Copy stellar-captive-core.cfg
- [ ] Copy horizon.env
- [ ] Configure nginx
- [ ] Create entrypoint.sh (db init, migrations, start)
- [ ] Test build and isolated execution

### Phase 4: Orchestration
- [ ] Create docker-compose.yml
- [ ] Configure the Docker network
- [ ] Configure volumes
- [ ] Configure healthchecks
- [ ] Test joint startup

### Phase 5: Validation
- [ ] Verify Core reaches Synced!
- [ ] Verify Horizon reaches ingestion
- [ ] Verify isolation (crash core → horizon keeps working)
- [ ] Compare performance with the single container

---

## 13. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|:-----|:------------|:-------|:-----------|
| Captive core cannot connect to the P2P network | Low | High | Check outbound ports, set PEER_PORT correctly |
| Duplicated buckets consume too much disk | High | Medium | Plan 15 GB+ of space, consider a shared bucket volume in the future |
| Different stellar-core versions between containers | Medium | High | Use the same base image for both |
| Horizon cannot start the captive core | Low | High | Check STELLAR_CORE_BINARY_PATH, binary permissions |
| PostgreSQL does not initialize correctly | Low | High | Check permissions, version, ports |
| Misconfigured nginx | Low | Medium | Test the Horizon healthcheck before configuring the proxy |
| Data loss when migrating volumes | Medium | High | Back up current volumes before migration |

---

## 14. Success Metrics

- [ ] Core container: `curl http://localhost:11626/info` → `"state": "Synced!"`
- [ ] Horizon container: `curl http://localhost:8000/` → `"core_latest_ledger"` > 0
- [ ] Core and Horizon are at nearby ledgers (gap < 100)
- [ ] Stop Core → Horizon keeps serving the API with historical data
- [ ] Stop Horizon → Core stays in P2P consensus
- [ ] `docker stats` shows resource isolation between containers
- [ ] Full startup completes in < 30 minutes (catch-up)

---

## 15. Next Steps

1. ✅ **Current phase:** Implementation plan approved
2. ⬜ Create `stellar-core/Dockerfile` and `stellar-core/entrypoint.sh`
3. ⬜ Create `stellar-horizon/Dockerfile` and `stellar-horizon/entrypoint.sh`
4. ⬜ Create the full `docker-compose.yml`
5. ⬜ Test local execution
6. ⬜ Validate metrics and performance
7. ⬜ Document results

---

## Appendix A: Example Configurations (extracted from the current container)

### Core Node Config (`stellar-core.cfg`)
```
HTTP_PORT=11626
PUBLIC_HTTP_PORT=true
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
PUBLIC_KEY="GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y"
ADDRESS="core-testnet1.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_001/{0} -o {1}"
```

### Captive Core Config (`stellar-captive-core.cfg`)
```
HTTP_PORT=11726
PUBLIC_HTTP_PORT=false
PEER_PORT=11725
DATABASE="sqlite3:///opt/stellar/horizon/captive-core/stellar.db"
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
UNSAFE_QUORUM=true
FAILURE_SAFETY=1
```

### Horizon Environment (`horizon.env`)
```
DATABASE_URL=postgres://stellar:<pass>@localhost/horizon
STELLAR_CORE_URL=http://localhost:11726
STELLAR_CORE_BINARY_PATH=/usr/bin/stellar-core
LOG_LEVEL=info
ENABLE_CAPTIVE_CORE_INGESTION=true
CAPTIVE_CORE_USE_DB=true
STELLAR_CAPTIVE_CORE_HTTP_PORT=11726
INGEST=true
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
HISTORY_ARCHIVE_URLS=https://history.stellar.org/prd/core-testnet/core_testnet_001
PORT=8001
CHECKPOINT_FREQUENCY=64
INGEST_DISABLE_STATE_VERIFICATION=True
```

---

## Appendix B: Network Diagram

```
                     INTERNET
                         │
            ┌────────────┴────────────┐
            │                         │
   history.stellar.org        sdf_testnet{1,2,3}
   (HTTPS 443)                (P2P 11625)
            │                         │
            └────────────┬────────────┘
                         │
              DOCKER HOST (localhost)
                         │
              ┌──────────┴──────────┐
              │                     │
     ┌────────▼────────┐   ┌───────▼────────┐
     │   stellar-core   │   │ stellar-horizon │
     │   172.20.0.10    │   │  172.20.0.11    │
     │                  │   │                 │
     │  ┌────────────┐  │   │ ┌─────────────┐ │
     │  │ P2P 11625  │──┼───┼─│→ outbound to│ │
     │  │ HTTP 11626 │  │   │ │ validators  │ │
     │  └────────────┘  │   │ └─────────────┘ │
     │                  │   │                 │
     │  Volume:         │   │ ┌─────────────┐ │
     │  core-data       │   │ │ Captive     │ │
     │                  │   │ │ Core        │ │
     │                  │   │ │ 11725 (P2P) │ │
     │                  │   │ │ 11726 (HTTP)│ │
     │                  │   │ └──────┬──────┘ │
     │                  │   │        │pipe    │
     │                  │   │ ┌──────▼──────┐ │
     │                  │   │ │ Horizon API │ │
     │                  │   │ │ :8001       │ │
     │                  │   │ └──────┬──────┘ │
     │                  │   │        │        │
     │                  │   │ ┌──────▼──────┐ │
     │                  │   │ │ PostgreSQL  │ │
     │                  │   │ │ :5432      │ │
     │                  │   │ └─────────────┘ │
     │                  │   │                 │
     │                  │   │ ┌─────────────┐ │
     │                  │   │ │ nginx :8000 │ │
     │                  │   │ └─────────────┘ │
     │                  │   └─────────────────┘
     └─────────────────┘
```

---

## Appendix C: docker-compose.yml (draft)

```yaml
version: "3.8"

networks:
  stellar-network:
    driver: bridge
    ipam:
      config:
        - subnet: "172.20.0.0/24"

volumes:
  core-data:
  horizon-data:
  pgdata:

services:
  stellar-core:
    build:
      context: ./stellar-core
      dockerfile: Dockerfile
    container_name: stellar-core
    networks:
      stellar-network:
        ipv4_address: 172.20.0.10
    ports:
      - "11625:11625/tcp"
      - "11626:11626/tcp"
    volumes:
      - core-data:/opt/stellar/core
      - core-logs:/var/log/stellar-core
    environment:
      - NETWORK_PASSPHRASE=Test SDF Network ; September 2015
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:11626/info"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s

  stellar-horizon:
    build:
      context: ./stellar-horizon
      dockerfile: Dockerfile
    container_name: stellar-horizon
    networks:
      stellar-network:
        ipv4_address: 172.20.0.11
    ports:
      - "8000:8000/tcp"
    volumes:
      - horizon-data:/opt/stellar/horizon
      - pgdata:/var/lib/postgresql/14/main
    environment:
      - NETWORK=testnet
      - LOG_LEVEL=info
    restart: unless-stopped
    depends_on:
      stellar-core:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 180s
```
