# Docker Stellar Core + Horizon Separated

Architecture with two independent containers for the Stellar Testnet:
- **stellar-core**: Validator node that participates in SCP consensus
- **stellar-horizon**: REST API + Captive Core + PostgreSQL

## Prerequisites

- Docker Desktop 4.x+
- ~15 GB of disk space (buckets + PostgreSQL)
- Internet connection (bucket downloads from the history archives)

## Structure

```
Docker-Core-Horizon-Separated/
├── docker-compose.yml              # Service orchestration
├── stellar-core/                   # Core container build
│   ├── Dockerfile
│   ├── stellar-core.cfg
│   └── entrypoint.sh
├── stellar-horizon/                # Horizon container build
│   ├── Dockerfile
│   ├── stellar-captive-core.cfg
│   ├── horizon.env
│   ├── nginx.conf
│   └── entrypoint.sh
└── 00-IMPLEMENTATION-PLAN.md    # Planning document
```

## How to use

### Build and start

```bash
docker-compose build --no-cache
docker-compose up -d
```

### Monitor logs

```bash
# Core logs
docker logs -f stellar-core

# Horizon logs
docker logs -f stellar-horizon

# Both
docker-compose logs -f
```

### Check status

```bash
# Core status (validator)
curl http://localhost:11626/info

# Horizon status (API)
curl http://localhost:8000/

# Horizon healthcheck
curl http://localhost:8000/health
```

### Stop

```bash
docker-compose down
```

### Clean data (restart from scratch)

```bash
docker-compose down -v
docker-compose up -d
```

## Ports

| Container | Port | External | Description |
|-----------|:-----:|:-------:|-----------|
| stellar-core | 11625 | Yes | P2P (connection with SDF validators) |
| stellar-core | 11626 | Yes | HTTP (admin, metrics, upgrades) |
| stellar-horizon | 8000 | Yes | Public HTTP (nginx → Horizon API) |
| stellar-horizon | 5432 | No | PostgreSQL (internal only) |
| stellar-horizon | 11725 | No | Captive Core P2P (internal) |
| stellar-horizon | 11726 | No | Captive Core HTTP (internal) |

## Volumes

| Volume | Container | Path | Content |
|--------|-----------|---------|----------|
| core-data | stellar-core | /opt/stellar/core | SQLite + Buckets + Config (~4.6 GB) |
| horizon-data | stellar-horizon | /opt/stellar/horizon | Captive Core SQLite + Buckets + Config (~4.7 GB) |
| pgdata | stellar-horizon | /var/lib/postgresql/14/main | PostgreSQL data (~5.3 GB) |

## Architecture

```
stellar-core (validator)       stellar-horizon (API)
┌──────────────────┐          ┌────────────────────────┐
│  SCP consensus    │          │  nginx :8000           │
│  P2P :11625       │          │    │                   │
│  HTTP :11626      │          │  Horizon :8001         │
│  SQLite + Buckets │          │    │                   │
│  (network state)  │          │  Captive Core :11726   │
└──────────────────┘          │    │                   │
                              │  PostgreSQL :5432       │
                              └────────────────────────┘

Independent: Horizon does NOT depend on the Core for ingestion.
Each one downloads its own buckets from the history archives.
```

## Observations

1. **Horizon does not depend on the Core**: With `ENABLE_CAPTIVE_CORE_INGESTION=true`, Horizon manages its own stellar-core as a subprocess. It does not need the stellar-core container to work.

2. **Duplicate buckets**: Both containers download buckets independently (~4.3 GB each = ~8.6 GB total). This is the normal behavior of the Stellar architecture (each captive core is independent).

3. **Independent catch-up**: Each container performs its own catch-up on startup. The Core takes ~30 min; Horizon takes ~30-60 min (depending on network state).

4. **STELLAR_CORE_URL**: In horizon.env, `STELLAR_CORE_URL=http://localhost:11726` points to the **local captive core** (not the external core node). This is for transaction submission, not ingestion.
