# Stellar Core — MainNet (Core Only)

**Single container** with stellar-core for the MainNet network.
No Horizon, no PostgreSQL, no captive core — just the SCP validator.

## Why core-only?

| With Horizon | Core Only |
|-------------|---------|
| ~170-300 GB on disk | ~50 GB on disk |
| 10-14 GB RAM | 3-6 GB RAM |
| 3 volumes | 1 volume |
| Syncs in 24-48h | Syncs in ~6-12h |
| PostgreSQL + Captive Core + Nginx | Only stellar-core |

## Usage

```bash
docker-compose up -d
```

## Status

```bash
curl http://localhost:11628/info
curl http://localhost:11628/metrics
```

## Ports

| Container | Host | Protocol | Description |
|-----------|:----:|:---------:|-----------|
| stellar-core-mainnet | 11627 | TCP | P2P (connection with MainNet validators) |
| stellar-core-mainnet | 11628 | TCP | HTTP (info, metrics, upgrades) |

## Estimated storage

| Item | Size |
|------|---------|
| Buckets (full state) | ~50 GB |
| stellar.db (SQLite) | ~200 MB |
| stellar.db-wal (WAL) | ~50 MB |
| **Total** | **~50 GB** |
