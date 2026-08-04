# Stellar Core — MainNet (Core Only)

**Container único** com stellar-core para rede MainNet.
Sem Horizon, sem PostgreSQL, sem captive core — só o validador SCP.

## Por que core-only?

| Com Horizon | Só Core |
|-------------|---------|
| ~170-300 GB em disco | ~50 GB em disco |
| 10-14 GB RAM | 3-6 GB RAM |
| 3 volumes | 1 volume |
| Sincroniza em 24-48h | Sincroniza em ~6-12h |
| PostgreSQL + Captive Core + Nginx | Só stellar-core |

## Uso

```bash
docker-compose up -d
```

## Status

```bash
curl http://localhost:11628/info
curl http://localhost:11628/metrics
```

## Portas

| Container | Host | Protocolo | Descrição |
|-----------|:----:|:---------:|-----------|
| stellar-core-mainnet | 11627 | TCP | P2P (conexão com validadores MainNet) |
| stellar-core-mainnet | 11628 | TCP | HTTP (info, métricas, upgrades) |

## Armazenamento estimado

| Item | Tamanho |
|------|---------|
| Buckets (estado completo) | ~50 GB |
| stellar.db (SQLite) | ~200 MB |
| stellar.db-wal (WAL) | ~50 MB |
| **Total** | **~50 GB** |
