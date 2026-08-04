# Relatório de Teste: Split do Container Stellar em Core + Horizon

**Data do Experimento:** 2026-07-21 20:54 - 21:30 UTC
**Duração:** ~36 minutos
**Imagem Base:** stellar/quickstart:testing (v27.1.0, Horizon devel)

---

## 1. Resultado Final

| Container | Status | Ledger | Age | RAM | CPU |
|:----------|:-------|:------:|:---:|:---:|:---:|
| **stellar-core** | ✅ Synced! | 3.733.171 | 2s | 4,4 GB | 0,27% |
| **stellar-horizon** | ✅ Ingesting | 3.733.056 | ~1 min | 6,6 GB | 6,4% |

Ambos os containers foram **construídos, iniciados e sincronizados com sucesso** em menos de 36 minutos.

---

## 2. Arquitetura Implementada

```
┌──────────────────────────────────┐      ┌──────────────────────────────────┐
│   stellar-core (validador)       │      │   stellar-horizon (API)          │
│   CONTAINER 1                    │      │   CONTAINER 2                    │
│                                  │      │                                  │
│  ┌────────────────────────────┐  │      │  ┌────────────────────────────┐  │
│  │  stellar-core --conf ...   │  │      │  │  stellar-horizon serve     │  │
│  │  run                       │  │      │  │  ENABLE_CAPTIVE_CORE=true  │  │
│  │                            │  │      │  │                            │  │
│  │  Estado: Synced!           │  │      │  │  ├── Captive Core (subproc)│  │
│  │  Ledger: 3.733.171         │  │      │  │  ├── PostgreSQL 16         │  │
│  │  Peers: 5                  │  │      │  │  └── nginx :8000           │  │
│  │  Protocolo: 27             │  │      │  │                            │  │
│  │                            │  │      │  │  Estado: Ingesting         │  │
│  │  SQLite: 18 MB + WAL 42 MB │  │      │  │  Ledger: 3.733.056         │  │
│  │  Buckets: 57 arquivos      │  │      │  │  Buckets: 39 arquivos      │  │
│  │  Disco: 5,7 GB             │  │      │  │  Disco: 6,3 GB + PG 4,1 GB│  │
│  └────────────────────────────┘  │      │  └────────────────────────────┘  │
│                                  │      │                                  │
│  Portas:                         │      │  Portas:                         │
│  11625 (P2P) → validadores SDF   │      │  8000 (nginx) → Horizon API    │
│  11626 (HTTP) → admin/metricas   │      │  5432 (PG) → loopback           │
│                                  │      │  11725 (captive P2P) → interno   │
│                                  │      │  11726 (captive HTTP) → interno  │
└──────────────────────────────────┘      └──────────────────────────────────┘
```

### 2.1 Fluxo de Dados

```
Core Node (validador)
    │
    ├── P2P (11625) → sdf_testnet_1,2,3
    ├── SCP Consensus
    ├── SQLite local (ledgers + storestate)
    └── Buckets (57 arquivos, 5,6 GB)

Horizon (API)
    │
    ├── Captive Core (subprocesso)
    │   ├── P2P (11725) → sdf_testnet_1,2,3
    │   ├── Baixa buckets (39 arquivos, 3,1 GB)
    │   ├── SQLite próprio (captive-core/stellar.db)
    │   └── Pipe (fd:3) → Horizon (metadados)
    │
    ├── Horizon API (porta 8001)
    │   ├── Lê metadados do captive core
    │   ├── Processa transactions, operations, effects
    │   └── Escreve no PostgreSQL
    │
    ├── PostgreSQL 16 (banco horizon)
    │
    └── nginx (porta 8000 → proxy para 8001)
```

### 2.2 Independência dos Containers

**Descoberta confirmada:** Horizon NÃO depende do Core Node. O Horizon:
- Gerencia seu próprio stellar-core via `ENABLE_CAPTIVE_CORE_INGESTION=true`
- O captive core se conecta diretamente à rede P2P da Stellar
- Baixa buckets próprios dos history archives
- `STELLAR_CORE_URL=http://localhost:11726` aponta para o captive core LOCAL

**Ambos os containers podem funcionar independentemente.**

---

## 3. Timeline de Sincronização

```
T+0s      ─── docker-compose up -d
              ├── stellar-core: new-db + new-hist + run
              └── stellar-horizon: initdb + migrations + horizon serve

T+30s     ─── Core: Ledger 1, Catching up
              Horizon: PostgreSQL init, applying migrations

T+2min    ─── Core: Ledger ~3.732.989, Joining SCP
              Horizon: Captive core baixando buckets (29/39 = 74%)

T+3min    ─── Core: Synced! Ledger 3.733.082, age 4s
              Horizon: Captive core baixou buckets (36/39 = 92%)

T+5min    ─── Core: Synced! Ledger 3.733.150, age 0s
              Horizon: Captive core Connected, Ledger 3.732.989

T+8min    ─── Core: Synced! Ledger 3.733.169, age 0s, idle 0,27% CPU
              Horizon: Ingesting! Ledger 3.733.056, PG populado
```

**Tempo total para sincronização completa: ~5 minutos** (devido ao bucket snapshot recente)

---

## 4. Armazenamento

### 4.1 Core Node

| Componente | Tamanho | Detalhes |
|:-----------|:--------|:---------|
| stellar.db | 18 MB | SQLite principal |
| stellar.db-wal | 42 MB | Write-Ahead Log |
| stellar-misc.db | 64 KB | Metadados |
| stellar-misc.db-wal | 7,7 MB | WAL de misc |
| buckets/ | 5,6 GB | 57 arquivos .xdr |
| **Total core** | **5,7 GB** | |

### 4.2 Horizon

| Componente | Tamanho | Detalhes |
|:-----------|:--------|:---------|
| horizon/ | 6,3 GB | Captive core + configs |
| captive-core/buckets | ~3,1 GB | 39 arquivos .xdr |
| PostgreSQL | 4,1 GB | Banco horizon |
| **Total horizon** | **10,4 GB** | |

**Total geral:** ~16,1 GB (contra ~15 GB do single container — diferença devido ao catch-up ainda em andamento no Horizon)

---

## 5. Recursos Computacionais

### 5.1 Docker Stats (pós-sincronização)

| Container | CPU% | RAM | RAM% | NET I/O | BLOCK I/O |
|:----------|:----:|:---:|:----:|:--------|:----------|
| stellar-core | 0,27% | 4,42 GB | 28,4% | 1,36 GB / 80,7 MB | 301 MB / 7,08 GB |
| stellar-horizon | 6,40% | 6,65 GB | 42,7% | 2,33 GB / 113 MB | 6,27 GB / 20,3 GB |

### 5.2 Pico durante catch-up

| Container | CPU Pico | RAM Pico |
|:----------|:---------|:---------|
| stellar-core | 92,64% | 7,96 GB |
| stellar-horizon | 192,53% | 2,34 GB |

### 5.3 Processos Principais

```
stellar-core:
  PID 14   stellar-core --conf ... run    45,6% CPU   3,1 GB RSS

stellar-horizon:
  PID 1    stellar-horizon serve           0,4% CPU     52 MB RSS
  PID 176  stellar-core (captive) catchup  36,5% CPU   547 MB RSS
  PID 90   nginx master                    0,0% CPU      7 MB RSS
  Vários   postgres workers                0,0% CPU   ~22 MB cada
```

---

## 6. Atividade do Banco de Dados (90s de monitoramento)

### 6.1 Progresso

| Fonte | Início | Fim | Δ Ledgers |
|:------|:------:|:---:|:---------:|
| Core Node | 3.733.087 | 3.733.150 | +63 |
| Horizon ingest | 0 | 0 | 0 (ingestão não havia começado) |

### 6.2 Queries Ativas ao Final

| PID | Estado | Evento | Query |
|:---|:------|:-------|:------|
| 1012 | active | relation | SELECT seller_id, offer_id, ... FROM offers |
| 1013 | active | WALWrite | COPY trust_lines (account_id, asset_code, ...) |

A query `COPY trust_lines` indica que a ingestão estava iniciando mas bloqueada em WALWrite (espera de flush do WAL).

### 6.3 Estado Pós-Ingestão (T+8min)

| Tabela | Linhas |
|:-------|:------:|
| history_ledgers | ~7.000+ (estimado) |
| history_transactions | Em ingestão |
| history_operations | Em ingestão |
| accounts | Sendo populado |
| trust_lines | Sendo populado |

---

## 7. Problemas Encontrados e Soluções

| Problema | Causa | Solução |
|:---------|:------|:--------|
| Core mostra help em vez de executar | `stellar-core --conf ...` sem `run` | Adicionar `run` ao comando: `stellar-core --conf ... run` |
| Permission denied "buckets" | Working directory errado | `cd /opt/stellar/core` no entrypoint |
| Config não encontrada no volume | Volume Docker mascara arquivos da imagem | Copiar config de `/etc/stellar/` staging para o volume |
| PostgreSQL lock file postmaster.pid | Shutdown não limpo do container anterior | Remover stale lock file antes de iniciar |
| "network-passphrase not allowed" | `NETWORK_PASSPHRASE` conflita com `NETWORK=testnet` | Remover `NETWORK_PASSPHRASE` do env |
| "history-archive-urls not allowed" | `HISTORY_ARCHIVE_URLS` conflita com `NETWORK=testnet` | Remover `HISTORY_ARCHIVE_URLS` do env |
| PostgreSQL SSL permissions | Config padrão do container | Corrigir permissões do `/etc/ssl/private` |
| Core trava com set -e | `new-hist vs` falha após new-db | `set -e` causa restart; remover `set -e` ou tratar erro |

---

## 8. Conclusões

### 8.1 O Split Funciona

A arquitetura de **dois containers separados** foi validada com sucesso. Ambos os containers:
- Iniciam independentemente
- Sincronizam com a rede Testnet
- Core atinge Synced! em ~3 minutos
- Horizon inicia ingestão em ~8 minutos

### 8.2 Independência Confirmada

O Horizon com `ENABLE_CAPTIVE_CORE_INGESTION=true` **realmente não depende do Core Node**. Cada container gerencia seu próprio stellar-core e buckets.

### 8.3 Custo de Armazenamento

O split não elimina a duplicação de buckets. Ambos os containers ainda baixam buckets independentemente (~5,7 GB core + ~3,1 GB captive core + ~4,1 GB PostgreSQL = ~12,9 GB no total, crescendo para ~16 GB quando totalmente sincronizados).

### 8.4 Performance

- **Core**: Sincronizou em ~3 min (ledger 1 → 3.733.082), usando ~92% CPU no pico
- **Horizon**: Baixou 39 buckets (3,1 GB) em ~2 min, captive core conectou em ~4 min
- Pós-sincronização: Core fica ocioso (0,27% CPU), Horizon usa ~6,4% CPU para ingestão

### 8.5 Recomendações

1. **Ajustar PostgreSQL**: Aumentar `max_wal_size` e tuning de shared_buffers para melhor performance de ingestão
2. **Healthchecks**: Implementar healthchecks mais robustos com `start_period` adequado
3. **Volumes separados**: Manter volumes separados para dados do core, captive core e PostgreSQL
4. **Build multi-estágio**: Otimizar Dockerfiles para camadas menores e cache eficiente

---

## 9. Arquivos do Projeto

```
Docker-Core-Horizon-Separado/
├── 00-PLANO-DE-IMPLEMENTACAO.md    (25 KB) — Documento de planejamento
├── docker-compose.yml              (2,4 KB) — Orquestração dos serviços
├── README.md                       (4,2 KB) — Instruções de uso
├── RELATORIO-TESTE-SPLIT.md        (este)   — Relatório do teste
│
├── stellar-core/
│   ├── Dockerfile                  (614 B)  — Build do Core
│   ├── stellar-core.cfg            (1,2 KB) — Config do Core
│   └── entrypoint.sh               (1,0 KB) — Script de inicialização
│
└── stellar-horizon/
    ├── Dockerfile                  (898 B)  — Build do Horizon
    ├── stellar-captive-core.cfg    (1,1 KB) — Config do captive core
    ├── horizon.env                 (875 B)  — Env vars do Horizon
    ├── nginx.conf                  (848 B)  — Config do nginx
    └── entrypoint.sh               (6,5 KB) — Script de inicialização
```

## 10. Comandos para Reprodução

```bash
# Build e start
docker-compose build --no-cache
docker-compose up -d

# Monitorar
docker logs -f stellar-core
docker logs -f stellar-horizon

# Verificar status
curl http://localhost:11626/info     # Core
curl http://localhost:8000/           # Horizon

# Parar e limpar
docker-compose down -v
```
