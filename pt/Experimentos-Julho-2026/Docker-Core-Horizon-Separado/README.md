# Docker Stellar Core + Horizon Separados

Arquitetura com dois containers independentes para Stellar Testnet:
- **stellar-core**: Nó validador que participa do consenso SCP
- **stellar-horizon**: API REST + Captive Core + PostgreSQL

## Pré-requisitos

- Docker Desktop 4.x+
- ~15 GB de espaço em disco (buckets + PostgreSQL)
- Conexão com internet (download de buckets dos history archives)

## Estrutura

```
Docker-Core-Horizon-Separado/
├── docker-compose.yml              # Orquestração dos serviços
├── stellar-core/                   # Build do container Core
│   ├── Dockerfile
│   ├── stellar-core.cfg
│   └── entrypoint.sh
├── stellar-horizon/                # Build do container Horizon
│   ├── Dockerfile
│   ├── stellar-captive-core.cfg
│   ├── horizon.env
│   ├── nginx.conf
│   └── entrypoint.sh
└── 00-PLANO-DE-IMPLEMENTACAO.md    # Documento de planejamento
```

## Como usar

### Build e start

```bash
docker-compose build --no-cache
docker-compose up -d
```

### Monitorar logs

```bash
# Logs do Core
docker logs -f stellar-core

# Logs do Horizon
docker logs -f stellar-horizon

# Ambos
docker-compose logs -f
```

### Verificar status

```bash
# Status do Core (validador)
curl http://localhost:11626/info

# Status do Horizon (API)
curl http://localhost:8000/

# Healthcheck do Horizon
curl http://localhost:8000/health
```

### Parar

```bash
docker-compose down
```

### Limpar dados (reinício do zero)

```bash
docker-compose down -v
docker-compose up -d
```

## Portas

| Container | Porta | Externo | Descrição |
|-----------|:-----:|:-------:|-----------|
| stellar-core | 11625 | Sim | P2P (conexão com validadores SDF) |
| stellar-core | 11626 | Sim | HTTP (admin, métricas, upgrades) |
| stellar-horizon | 8000 | Sim | HTTP público (nginx → Horizon API) |
| stellar-horizon | 5432 | Não | PostgreSQL (apenas interno) |
| stellar-horizon | 11725 | Não | Captive Core P2P (interno) |
| stellar-horizon | 11726 | Não | Captive Core HTTP (interno) |

## Volumes

| Volume | Container | Caminho | Conteúdo |
|--------|-----------|---------|----------|
| core-data | stellar-core | /opt/stellar/core | SQLite + Buckets + Config (~4,6 GB) |
| horizon-data | stellar-horizon | /opt/stellar/horizon | Captive Core SQLite + Buckets + Config (~4,7 GB) |
| pgdata | stellar-horizon | /var/lib/postgresql/14/main | PostgreSQL data (~5,3 GB) |

## Arquitetura

```
stellar-core (validador)       stellar-horizon (API)
┌──────────────────┐          ┌────────────────────────┐
│  Consenso SCP     │          │  nginx :8000           │
│  P2P :11625       │          │    │                   │
│  HTTP :11626      │          │  Horizon :8001         │
│  SQLite + Buckets │          │    │                   │
│  (estado rede)    │          │  Captive Core :11726   │
└──────────────────┘          │    │                   │
                              │  PostgreSQL :5432       │
                              └────────────────────────┘

Independentes: Horizon NÃO depende do Core para ingestão.
Cada um baixa seus próprios buckets dos history archives.
```

## Observações

1. **Horizon não depende do Core**: Com `ENABLE_CAPTIVE_CORE_INGESTION=true`, o Horizon gerencia seu próprio stellar-core como subprocesso. Ele não precisa do container stellar-core para funcionar.

2. **Buckets duplicados**: Ambos os containers baixam buckets independentemente (~4,3 GB cada = ~8,6 GB total). Isso é o comportamento normal da arquitetura Stellar (cada captive core é independente).

3. **Catch-up independente**: Cada container faz seu próprio catch-up ao iniciar. O Core leva ~30 min, o Horizon leva ~30-60 min (dependendo do estado da rede).

4. **STELLAR_CORE_URL**: No horizon.env, `STELLAR_CORE_URL=http://localhost:11726` aponta para o **captive core local** (não o core node externo). Isso é para submissão de transações, não para ingestão.
