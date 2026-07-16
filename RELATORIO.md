# Relatório Completo: Docker Stellar Testnet + Horizon

## Sumário

1. [Especificações da Máquina e Docker](#1-especificações-da-máquina-e-docker)
2. [Arquitetura Geral do Sistema](#2-arquitetura-geral-do-sistema)
3. [Processo de Inicialização (Startup)](#3-processo-de-inicialização)
4. [Serviços do Container](#4-serviços-do-container)
5. [Conexões de Rede Externas](#5-conexões-de-rede-externas)
6. [Bancos de Dados](#6-bancos-de-dados)
7. [Bucket List — Armazenamento de Estado](#7-bucket-list--armazenamento-de-estado)
8. [Fluxo Completo de Sincronização](#8-fluxo-completo-de-sincronização)
9. [Diagramas Mermaid](#9-diagramas-mermaid)
10. [Conclusão](#10-conclusão)

---

## 1. Especificações da Máquina e Docker

### Máquina Host

| Parâmetro | Valor |
|---|---|
| **Sistema Operacional** | Microsoft Windows 11 Pro |
| **Processador** | AMD Ryzen 7 5700X3D 8-Core (16 logical processors) |
| **Memória RAM Total** | 31.9 GB (33,437,944 KB) |
| **Memória RAM Livre** | 11.6 GB (12,154,248 KB) |
| **Docker Desktop** | v29.1.3 |
| **Docker Compose** | v5.0.0-desktop.1 |
| **WSL2 Kernel** | 6.18.33.2-microsoft-standard-WSL2 |
| **Docker Engine** | 16 CPUs, 15.56 GiB total memory |

### Docker Compose

```yaml
services:
  stellar:
    image: stellar/quickstart:testing
    container_name: stellar-testnet
    ports:
      - "8000:8000"       # Horizon API
      - "11625:11625"     # Stellar Core P2P (peer)
      - "11626:11626"     # Stellar Core HTTP (info/upgrades)
    environment:
      NETWORK: testnet
      ENABLE: core,horizon
      LOG_LEVEL: info
    volumes:
      - stellar-data:/opt/stellar
    stdin_open: true
    tty: true
    restart: unless-stopped

volumes:
  stellar-data:
```

### Container

| Parâmetro | Valor |
|---|---|
| **Imagem** | `stellar/quickstart:testing` (sha256:ee95e7...) |
| **Container ID** | `4fbe5ce9b7cd` |
| **IP Interno (Docker)** | 172.18.0.2 |
| **Gateway** | 172.18.0.1 |
| **Entrypoint** | `/start` |
| **Driver de Armazenamento** | overlayfs |
| **Volumes Montados** | `stellar-data:/opt/stellar` (~5.4 GB de dados) |
| **Restart Policy** | unless-stopped |

---

## 2. Arquitetura Geral do Sistema

A imagem `stellar/quickstart:testing` é uma "bateria inclusa" que empacota **todos** os componentes da Stellar em uma única imagem Docker, gerenciados pelo **Supervisor** (supervisord). Diferentemente de uma instalação production-grade com containers separados, o quickstart roda tudo no mesmo container para simplificar desenvolvimento e testes.

### Componentes Instalados

| Componente | Versão | Finalidade |
|---|---|---|
| **Stellar Core (node)** | v27.1.0 | Participa do consenso na testnet |
| **Stellar Core (captive)** | v27.1.0 | Apenas para servir dados ao Horizon (não participa do consenso) |
| **Horizon** | devel (go1.26.4) | API REST para consulta de dados da rede |
| **PostgreSQL** | 14 (Alpine) | Banco de dados principal do Horizon |
| **Nginx** | — | Reverse proxy para o Horizon (porta 8000) |
| **Supervisor** | — | Gerenciador de processos (PID 1) |

### Árvore de Diretórios do Container

```
/opt/stellar/
├── core/                    # Stellar Core Node
│   ├── bin/start            # Script de inicialização
│   ├── etc/
│   │   ├── stellar-core.cfg # Configuração principal
│   │   └── env              # Variáveis de ambiente do core
│   ├── buckets/             # Bucket list (estado completo da ledger)
│   ├── stellar.db           # SQLite (meta-dados do core)
│   ├── stellar-misc.db      # SQLite miscelânea
│   └── .quickstart-initialized
├── horizon/                 # Horizon API Server
│   ├── bin/start            # Script de inicialização
│   ├── bin/horizon          # Binário do Horizon
│   ├── etc/
│   │   ├── horizon.env      # Configuração do Horizon
│   │   └── stellar-captive-core.cfg  # Config do captive core
│   └── captive-core/
│       ├── stellar.db       # SQLite do captive core
│       ├── stellar-misc.db
│       └── captive-core/
│           ├── stellar-core.conf  # Config gerada do captive core
│           └── buckets/           # Buckets do captive core
├── postgresql/              # PostgreSQL
│   ├── data/                # Dados do banco
│   ├── etc/
│   │   ├── postgresql.conf  # Config do PostgreSQL
│   │   ├── pg_hba.conf      # Autenticação
│   │   └── pg_ident.conf
│   └── .pgpass              # Senha armazenada
├── nginx/                   # Nginx reverse proxy
│   ├── bin/start
│   └── etc/
│       └── nginx.conf
├── supervisor/              # Supervisord
│   └── etc/
│       └── supervisord.conf
└── stellar-rpc/             # RPC Server (não ativado no nosso setup)
```

---

## 3. Processo de Inicialização

O entrypoint `/start` (script bash de ~600 linhas) orquestra toda a inicialização. O fluxo é:

### Fase 1: Configuração de Rede (process_args)

Com base na variável `NETWORK=testnet`, o script define:

```bash
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
```

Calcula o `NETWORK_ID` (hash sha256 da passphrase) e deriva as chaves da conta raiz da rede.

### Fase 2: Copy Defaults (copy_defaults)

Copia arquivos de configuração padrão de `/opt/stellar-default/{common,testnet}/` para os diretórios de cada serviço. Isso só acontece na **primeira execução** (diretórios vazios). Em execuções posteriores, os diretórios já existem (persistidos no volume) e o copy é pulado.

### Fase 3: Inicialização do Banco (init_db)

- Gera senha aleatória para PostgreSQL (exibida no log)
- Executa `initdb` no PostgreSQL
- Cria databases: `horizon` (e `core` se `CORE_USE_POSTGRES=true`)
- Cria usuário `stellar` com privilégios
- Para o PostgreSQL (será reiniciado pelo Supervisor depois)

### Fase 4: Inicialização do Stellar Core (init_stellar_core)

- Substitui placeholders no `stellar-core.cfg`:
  - `__NETWORK__` → `"Test SDF Network ; September 2015"`
  - `__MANUAL_CLOSE__` → `false`
  - `__DATABASE__` → `sqlite3:///opt/stellar/core/stellar.db`
- Executa `stellar-core new-db` para criar o schema SQLite
- Cria o arquivo `.quickstart-initialized` para evitar repetição

### Fase 5: Inicialização do Horizon (init_horizon)

- Substitui placeholders no `horizon.env` e `stellar-captive-core.cfg`
- Executa `horizon db init` para criar as 33 tabelas no PostgreSQL
- Cria o arquivo `.quickstart-initialized`

### Fase 6: Inicialização do Supervisor (exec_supervisor)

O Supervisor gerencia os processos filhos com estas prioridades:

| Prioridade | Serviço | Autostart | Descrição |
|---|---|---|---|
| 10 | postgresql | false | Banco de dados |
| 20 | stellar-core | false | Nó de consenso |
| 30 | horizon | false | API server |
| 50 | nginx | **true** | Reverse proxy |

Os serviços marcados como `autostart=false` são iniciados manualmente pelo script `start_optional_services()` após o Supervisor estar rodando.

### Fase 7: Upgrade Local e Monitoramento

- `upgrade_local()`: Apenas para rede `local` (config upgrades)
- `service_status()`: Loops que monitoram o status de cada stellar-core e horizon, exibindo no log
- `start_optional_services()`: Inicia postgresql → stellar-core → horizon (nesta ordem)

---

## 4. Serviços do Container

### 4.1 Supervisor

- **PID:** 1
- **Comando:** `/usr/bin/python3 /bin/supervisord -n -c /opt/stellar/supervisor/etc/supervisord.conf`
- **Porta:** 9001 (localhost, interface HTTP)
- **Função:** Process manager. Mantém todos os serviços rodando, reinicia se necessário.
- **Config:** Lê arquivos de `/opt/stellar/supervisor/etc/supervisord.conf.d/`

### 4.2 Stellar Core — Nó de Consenso (Node)

- **PID:** 291
- **Usuário:** stellar
- **Comando:** `/usr/bin/stellar-core --conf /opt/stellar/core/etc/stellar-core.cfg run`
- **Uso de Memória:** ~2.8 GB (17.6% do total do container)
- **CPU:** ~12% (pode chegar a 100% durante catchup)
- **Portas:**
  - `11625` (P2P — escuta 0.0.0.0) — comunicação com peers
  - `11626` (HTTP — escuta 0.0.0.0) — API de info/upgrades

#### Configuração Completa

```ini
HTTP_PORT=11626
PUBLIC_HTTP_PORT=true
LOG_FILE_PATH="/var/log/stellar-core/stellar-core-{datetime:%Y-%m-%d_%H-%M-%S}.log"
MANUAL_CLOSE=false

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
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y"
ADDRESS="core-testnet1.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_001/{0} -o {1}"

[[VALIDATORS]]
NAME="sdf_testnet_2"
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GCUCJTIYXSOXKBSNFGNFWW5MUQ54HKRPGJUTQFJ5RQXZXNOLNXYDHRAP"
ADDRESS="core-testnet2.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_002/{0} -o {1}"

[[VALIDATORS]]
NAME="sdf_testnet_3"
HOME_DOMAIN="testnet.stellar.org"
PUBLIC_KEY="GC2V2EFSXN6SQTWVYA5EPJPBWWIMSD2XQNKUOHGEKB535AQE2I6IXV2Z"
ADDRESS="core-testnet3.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_003/{0} -o {1}"
```

**Parâmetros importantes:**

| Parâmetro | Valor | Significado |
|---|---|---|
| `CATCHUP_RECENT` | 100 | Quantos ledgers recentes pegar via history archive |
| `UNSAFE_QUORUM` | true | Aceita quorum mesmo sem configuração de nós confiáveis (safe para testnet) |
| `FAILURE_SAFETY` | 1 | Tolerância a falhas (f = 1, precisa de 3 validadores) |
| `MANUAL_CLOSE` | false | Fechamento automático de ledger (não manual) |
| `DATABASE` | sqlite3://... | Banco de dados local, não usa PostgreSQL |

**Função:** Participa ativamente do consenso SCP (Stellar Consensus Protocol), mantém conexões P2P com peers da testnet, valida transações, e atualiza sua ledger local. É o "nó completo" da rede.

### 4.3 Stellar Core — Captive Core (Horizon)

- **PID:** 3985
- **Usuário:** stellar
- **Comando:** `/usr/bin/stellar-core --conf /opt/stellar/horizon/captive-core/captive-core/stellar-core.conf --console run --metadata-output-stream fd:3`
- **Uso de Memória:** ~2.9 GB (17.9%)
- **CPU:** ~4.5%
- **Portas:**
  - `11725` (P2P — escuta 0.0.0.0)
  - `11726` (HTTP — escuta localhost:11726)

#### Diferenças Cruciais entre Node e Captive Core

| Característica | Node (PID 291) | Captive Core (PID 3985) |
|---|---|---|
| **Participa do consenso?** | Sim | **Não** |
| **Conecta a peers?** | Sim (P2P) | Sim (apenas para catchup inicial) |
| **Database** | SQLite (`stellar.db`) | SQLite (`captive-core/stellar.db`) |
| **Bucket list** | Compartilhada | Isolada (própria) |
| **Porta HTTP** | 11626 (pública) | 11726 (localhost apenas) |
| **Porta P2P** | 11625 (pública) | 11725 (pública) |
| **Iniciado por?** | Supervisor → `core/bin/start` | Horizon (como subprocesso) |
| **Ciclo de vida** | Permanente | Efêmero (sobe/desce com a ingestão) |
| **Modo de execução** | `run` (normal) | `--console run --metadata-output-stream fd:3` (streaming de metadados) |
| **Bucketlist DB** | Usa index page size padrão | `BUCKETLIST_DB_INDEX_PAGE_SIZE_EXPONENT=12`, `BUCKETLIST_DB_MEMORY_FOR_CACHING=0` |
| **Backfill restore** | Não | `BACKFILL_RESTORE_META=true` |

**Função:** O Captive Core é um stellar-core **descartável** que o Horizon inicia como subprocesso APENAS para fazer ingestão de dados. Ele não participa do consenso, não aceita conexões de peers (apenas faz catchup inicial de archives), e é descartado/recriado conforme necessário. O Horizon lê o output do metadata stream (`fd:3`) para processar transações e alimentar o PostgreSQL.

### 4.4 Horizon API Server

- **PID:** 349
- **Usuário:** stellar
- **Comando:** `/usr/bin/stellar-horizon`
- **Uso de Memória:** ~182 MB (1.1%)
- **CPU:** ~8.8%
- **Porta:** 8001 (interna), exposta como 8000 via Nginx

#### Configuração (horizon.env)

```bash
export DATABASE_URL="postgres://stellar:s9YVDakFZwTcrb7h@localhost/horizon"
export STELLAR_CORE_URL="http://localhost:11726"
export STELLAR_CORE_BINARY_PATH=/usr/bin/stellar-core
export LOG_LEVEL="info"
export ENABLE_CAPTIVE_CORE_INGESTION="true"
export CAPTIVE_CORE_USE_DB=true
export INGEST="true"
export PER_HOUR_RATE_LIMIT="72000"
export NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
export HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
export ADMIN_PORT=6060
export PORT=8001
export CHECKPOINT_FREQUENCY=64
export INGEST_DISABLE_STATE_VERIFICATION=True
export CAPTIVE_CORE_CONFIG_PATH=/opt/stellar/horizon/etc/stellar-captive-core.cfg
export CAPTIVE_CORE_STORAGE_PATH=/opt/stellar/horizon/captive-core
export STELLAR_CORE_VERSION="v27.1.0"
```

**Função:** O Horizon é o servidor de API REST que permite consultar saldos, transações, operações, efeitos, etc. Ele faz **ingestão** dos dados: lê o ledger do Captive Core, processa e armazena no PostgreSQL de forma estruturada (histórico + state atual).

### 4.5 PostgreSQL

- **PID:** 330
- **Usuário:** postgres
- **Versão:** 14 (Alpine)
- **Uso de Memória:** ~25 MB (0.1% — apenas o processo principal; os workers somam mais)
- **Porta:** 5432

#### Configuração Relevante

| Parâmetro | Valor |
|---|---|
| `max_connections` | 150 |
| `shared_buffers` | 128 MB |
| `listen_addresses` | `*` |
| `ssl` | true (certificado snakeoil) |
| `data_directory` | `/opt/stellar/postgresql/data` |

#### Autenticação (pg_hba.conf)

```
local   all   postgres   peer
local   all   all        md5
host    all   all        127.0.0.1/32    md5
host    all   all        0.0.0.0/0       md5
host    all   all        ::1/128         md5
```

### 4.6 Nginx

- **PID:** 288 (master), 289 (worker)
- **Usuário:** www-data
- **Porta:** 8000 (externa)
- **Função:** Reverse proxy. Encaminha requisições da porta 8000 para o Horizon (porta 8001). Também inclui arquivos de `conf.d/` para outros serviços (RPC, Friendbot, Lab).

---

## 5. Conexões de Rede Externas

### Conexões Ativas (ESTABLISHED)

O stellar-core mantém conexões P2P persistentes com peers da testnet. Durante nossa execução, capturamos:

| IP do Peer | Porta | Status |
|---|---|---|
| 13.223.55.158 | 11625 | ESTAB |
| 44.204.146.210 | 11625 | ESTAB |
| 3.85.105.105 | 11625 | ESTAB |
| 44.206.255.84 | 11625 | ESTAB |
| 44.213.67.110 | 11625 | ESTAB |
| 98.91.174.101 | 11625 | ESTAB (2 conexões) |
| 141.98.219.89 | 11625 | ESTAB |
| 54.159.155.163 | 11625 | ESTAB |
| 18.220.162.149 | **11725** | ESTAB (captive core) |

### Conexões em andamento (SYN-SENT)

| IP do Peer | Porta |
|---|---|
| 107.21.193.235 | 30020 |
| 89.124.115.249 | 11625 |
| 200.129.247.55 | 11625 |
| 18.212.206.26 | 30020 |

### Endpoints de History Archive

O stellar-core baixa o estado histórico destas URLs:

| URL | Descrição |
|---|---|
| `http://history.stellar.org/prd/core-testnet/core_testnet_001/{0}` | Archive 1 (SDF) |
| `http://history.stellar.org/prd/core-testnet/core_testnet_002/{0}` | Archive 2 (SDF) |
| `http://history.stellar.org/prd/core-testnet/core_testnet_003/{0}` | Archive 3 (SDF) |

### Validadores da Testnet (SDF)

| Nome | Chave Pública | Endereço |
|---|---|---|
| sdf_testnet_1 | `GDKXE2OZMJI...` | core-testnet1.stellar.org |
| sdf_testnet_2 | `GCUCJTIYXSOX...` | core-testnet2.stellar.org |
| sdf_testnet_3 | `GC2V2EFSXN6...` | core-testnet3.stellar.org |

---

## 6. Bancos de Dados

### 6.1 PostgreSQL (Horizon)

**Database:** `horizon`
**Usuário:** `stellar`
**Tamanho total:** ~1.2 GB

#### 33 Tabelas (com tamanhos)

| Tabela | Tamanho | Função |
|---|---|---|
| `accounts` | **497 MB** | Contas com saldos e sequências |
| `accounts_signers` | **428 MB** | Signers de cada conta |
| `accounts_data` | **94 MB** | Data entries das contas |
| `trust_lines` | **107 MB** | Trust lines (saldo de assets não-nativos) |
| `offers` | **12 MB** | Ofertas em aberto |
| `exp_asset_stats` | **23 MB** | Estatísticas de assets |
| `history_transactions` | **10 MB** | Transações históricas |
| `history_operations` | **3.3 MB** | Operações históricas |
| `claimable_balances` | **5 MB** | Claimable balances |
| `contract_asset_balances` | **6 MB** | Balances de contratos Soroban |
| `history_ledgers` | **320 kB** | Metadados de ledgers |
| `history_effects` | **536 kB** | Efeitos de operações |
| `history_operation_participants` | **384 kB** | Participantes de operações |
| `history_transaction_participants` | **312 kB** | Participantes de transações |
| `history_assets` | **8 kB** | Assets históricos |
| `liquidity_pools` | **872 kB** | Pools de liquidez |
| `gorp_migrations` | **16 kB** | Controle de migrações |
| `key_value_store` | **56 kB** | KV store auxiliar |
| `asset_contracts`, `account_filter_rules`, `asset_filter_rules` | — | Regras de filtro/gas |
| `history_claimable_balances` | 16 kB | Claimable balances históricas |
| `history_liquidity_pools` | 8 kB | Liquidity pools históricas |
| `history_trades`, `history_trades_60000` | — | Trades históricos |
| `contract_asset_stats` | 192 kB | Stats de contratos |
| `history_operation_*`, `history_transaction_*` | — | Tabelas de junção |

### 6.2 SQLite (Stellar Core Node)

**Arquivo:** `/opt/stellar/core/stellar.db`
**Tamanho:** ~18 MB (com WAL: ~62 MB)

Armazena metadados do stellar-core: ledger headers, contas de consenso, quorum sets, etc.

**Arquivo:** `/opt/stellar/core/stellar-misc.db` (~22 MB com WAL)

Armazena dados miscelâneos (peers conhecidos, bans, etc.)

### 6.3 SQLite (Captive Core - Horizon)

**Arquivo:** `/opt/stellar/horizon/captive-core/stellar.db`
**Tamanho:** ~21 MB (com WAL: ~33 MB)

**Arquivo:** `/opt/stellar/horizon/captive-core/stellar-misc.db` (~14 MB com WAL)

---

## 7. Bucket List — Armazenamento de Estado

### O que é a Bucket List?

A **Bucket List** é o mecanismo de armazenamento de estado do Stellar Core. Diferente de um banco de dados tradicional, ela é uma estrutura de dados **imutável e baseada em merge** que armazena o estado completo da ledger (contas, saldos, offers, trust lines, etc.) em arquivos XDR chamados "buckets".

### Características

- **Imutável:** Buckets nunca são modificados após criados. Mudanças geram NOVOS buckets.
- **Níveis (Levels):** A bucket list tem 11 níveis (0-10). Cada nível contém buckets que representam snapshots do estado em diferentes escalas de tempo.
- **Merge:** Periodicamente, buckets de níveis inferiores são mergeados em níveis superiores (compaction).
- **Hashes:** Cada bucket é identificado por um hash SHA-256 do seu conteúdo.
- **Formato:** Arquivos `.xdr` (XDR serialization) com arquivos `.index` para lookup.

### Estrutura dos Diretórios

**Node Core** (`/opt/stellar/core/buckets/`):
```
buckets/
├── bucket-<hash>.xdr       # Dados do bucket (XDR)
├── bucket-<hash>.index     # Índice do bucket
├── history/                # Dados históricos (ledger, transactions, results)
├── meta-debug/             # Meta-dados de debug
│   ├── debug-tx-set.xdr
│   └── meta-debug-<ledger>-<hash>.xdr.gz
├── publishqueue/           # Fila de publicação
└── tmp/                    # Arquivos temporários durante merge
```

**Tamanho total:** ~4.7 GB (node) + ~5.4 GB (captive core) = ~10 GB

### Maiores Buckets

| Bucket (Node) | Tamanho |
|---|---|
| `bucket-ff26b4f5...xdr` | **822 MB** |
| `bucket-eb7625ce...xdr` | **639 MB** |
| `bucket-d8522ede...xdr` | **629 MB** |
| `bucket-b2a2c09a...xdr` | **371 MB** |
| `bucket-8a27deda...xdr` | **473 MB** |

### Como o Bucket List se Conecta ao Sistema

```mermaid
flowchart LR
    subgraph "External"
        HA[History Archives<br/>https://history.stellar.org]
        P2P[Peers P2P<br/>core-testnet1/2/3]
    end

    subgraph "Stellar Core Node"
        BC[Bucket List<br/>4.7 GB]
        SQL1[(SQLite<br/>stellar.db)]
    end

    subgraph "Captive Core (Horizon)"
        BC2[Bucket List<br/>5.4 GB<br/>captive-core/buckets/]
        SQL2[(SQLite<br/>captive-core/stellar.db)]
    end

    subgraph "Horizon"
        H[Horizon API]
        PG[(PostgreSQL<br/>33 tabelas)]
    end

    P2P -->|SCP Consensus| BC
    HA -->|Download inicial| BC
    BC -->|Snapshot state| SQL1

    HA -->|Catchup| BC2
    BC2 -->|Metadata stream| H
    H -->|Ingestion| PG
    
    H -->|Query| PG
    User -->|HTTP :8000| H
```

### Processo de Catchup

1. **Determinar trigger ledger:** O core consulta peers para saber qual o ledger mais recente
2. **Download de state files:** Baixa arquivos JSON de history que descrevem qual snapshot baixar
3. **Download de buckets:** Baixa buckets do history archive (dezenas de arquivos, até 800 MB cada)
4. **Verificação:** Verifica hashes SHA-256 de cada bucket
5. **Apply:** Aplica os buckets na bucket list local
6. **Download de checkpoints:** Baixa ledgers incrementais (checkpoints) até o estado atual
7. **Apply buffered ledgers:** Aplica ledgers em buffer até alcançar o estado mais recente
8. **Synced!** — O nó está sincronizado e começa a participar do consenso

---

## 8. Fluxo Completo de Sincronização

### Timeline Real (do nosso container)

| Tempo | Evento | Ledger |
|---|---|---|
| 00:57:23 | Container inicia | — |
| 00:57:30 | PostgreSQL disponível | — |
| 00:57:33 | stellar-core node inicia | — |
| 00:57:35 | Horizon inicia (modo ingestão) | — |
| 00:57:35 | **Catching up** — ETA: 280s | 3,629,377 |
| 00:57:35 | Download de state files + buckets | 3,629,311 |
| 00:59:xx | Download de buckets: 8% → 70% | — |
| 01:04:xx | Download completo → Applying buckets | — |
| 01:05:xx | **Succeeded: download-verify-apply-buckets** | 3,629,309 |
| 01:05:xx | Download de checkpoints restantes | — |
| 01:05:xx | Captive Core **Connected** | 3,629,376 |
| 01:08:xx | Node **Synced!** | 3,629,436 |
| 01:09:xx | Horizon core: downloading ledger files | 3,629,375 |
| 01:11:23 | **Horizon: ingestion caught up** | 3,629,501 |
| 01:11:48 | Core latest ledger | 3,629,501 |

**Tempo total para sincronizar:** ~14 minutos (primeira execução, com buckets quentes em cache)

---

## 9. Diagramas Mermaid

### Diagrama 1: Arquitetura Geral de Serviços

```mermaid
graph TB
    subgraph "Container: stellar-testnet"
        S[Supervisord<br/>PID 1]
        
        subgraph "Gerenciados pelo Supervisor"
            direction LR
            PG[("PostgreSQL<br/>:5432")]
            CN[Stellar Core Node<br/>PID 291<br/>:11625 :11626]
            HZ[Horizon API<br/>PID 349<br/>:8001]
            NX[Nginx<br/>PID 288<br/>:8000]
        end
        
        CC[Captive Core<br/>PID 3985<br/>Não-gerenciado<br/>:11725 :11726]
    end
    
    S -->|start_optional_services| PG
    S -->|start_optional_services| CN
    S -->|start_optional_services| HZ
    S -->|autostart=true| NX
    
    HZ -->|subprocess| CC
    HZ -->|consulta| PG
    HZ -->|consulta| CC
    
    NX -->|reverse proxy :8000| HZ
    
    CN -->|informa status| HZ
```

### Diagrama 2: Conexões de Rede

```mermaid
flowchart LR
    subgraph "Mundo Externo"
        V1[Validator sdf_testnet_1<br/>core-testnet1.stellar.org]
        V2[Validator sdf_testnet_2<br/>core-testnet2.stellar.org]
        V3[Validator sdf_testnet_3<br/>core-testnet3.stellar.org]
        HA[History Archives<br/>history.stellar.org]
        P[Peers aleatórios<br/>~10 conexões]
    end
    
    subgraph "Container"
        Node[Stellar Core Node<br/>:11625 P2P<br/>:11626 HTTP]
        CC[Captive Core<br/>:11725 P2P<br/>:11726 HTTP]
        
        Node -- "P2P :11625" --> V1
        Node -- "P2P :11625" --> V2
        Node -- "P2P :11625" --> V3
        Node -- "P2P :11625" --> P
        
        CC -- "P2P :11725" --> P
        
        Node -->|"HISTORY curl"| HA
        CC -->|"HISTORY curl"| HA
    end
    
    User[Usuário] -->|"HTTP :8000"| Node
```

### Diagrama 3: Fluxo de Dados (Bucket List → Horizon)

```mermaid
sequenceDiagram
    participant HA as History Archive
    participant CC as Captive Core
    participant H as Horizon
    participant PG as PostgreSQL
    participant User as Usuário

    Note over CC: Início da Ingestão
    
    CC->>HA: Baixa state files (JSON)
    CC->>HA: Baixa buckets (XDR)
    CC->>CC: Verifica hashes SHA-256
    CC->>CC: Aplica buckets na bucket list
    CC->>HA: Baixa checkpoints incrementais
    CC->>CC: Aplica ledgers em buffer
    
    loop A cada checkpoint (64 ledgers)
        CC->>H: Stream de metadados (fd:3)
        H->>H: Processa transações
        H->>PG: Insere dados históricos
        H->>PG: Atualiza estado (accounts, offers, etc.)
    end
    
    Note over H,PG: Ingestão completa
    
    User->>H: GET /accounts/:id
    H->>PG: SELECT * FROM accounts WHERE...
    PG-->>H: Dados da conta
    H-->>User: Response JSON
    
    User->>H: GET /transactions
    H->>PG: SELECT * FROM history_transactions
    PG-->>H: Transações
    H-->>User: Response JSON
```

### Diagrama 4: Hierarquia da Bucket List

```mermaid
graph TB
    subgraph "Bucket List (Níveis 0-10)"
        L0[Level 0<br/>2 buckets<br/>~26 KB]
        L1[Level 1<br/>2 buckets<br/>~47 KB]
        L2[Level 2<br/>2 buckets<br/>~1.6 MB]
        L3[Level 3<br/>2 buckets<br/>~1.1 MB]
        L4[Level 4<br/>2 buckets<br/>~1.8 MB]
        L5[Level 5<br/>2 buckets<br/>~6.5 MB]
        L6[Level 6<br/>2 buckets<br/>~40 MB]
        L7[Level 7<br/>2 buckets<br/>~103 MB]
        L8[Level 8<br/>2 buckets<br/>~211 MB]
        L9[Level 9<br/>2 buckets<br/>~629 MB]
        L10[Level 10<br/>2 buckets<br/>~822 MB]
    end
    
    L0 -->|merge| L1
    L1 -->|merge| L2
    L2 -->|merge| L3
    L3 -->|merge| L4
    L4 -->|merge| L5
    L5 -->|merge| L6
    L6 -->|merge| L7
    L7 -->|merge| L8
    L8 -->|merge| L9
    L9 -->|merge| L10
    
    style L0 fill:#c8e6c9
    style L1 fill:#c8e6c9
    style L2 fill:#a5d6a7
    style L3 fill:#a5d6a7
    style L4 fill:#81c784
    style L5 fill:#81c784
    style L6 fill:#66bb6a
    style L7 fill:#66bb6a
    style L8 fill:#4caf50
    style L9 fill:#43a047
    style L10 fill:#388e3c
```

### Diagrama 5: Fluxo de Inicialização

```mermaid
flowchart TD
    A["/start<br/>Entrypoint"] --> B[process_args<br/>Define NETWORK, vars]
    B --> C[copy_defaults<br/>Copia configs para /opt/stellar/]
    C --> D{Primeira<br/>execução?}
    D -->|Sim| E[init_db<br/>PostgreSQL initdb + criação]
    D -->|Não| F[Pula inicialização]
    E --> F
    F --> G[init_stellar_core<br/>new-db + configuração]
    G --> H[init_horizon<br/>db init + 33 tabelas]
    H --> I[stop_postgres<br/>Para o PG temporariamente]
    I --> J[exec_supervisor<br/>Inicia o supervisord]
    J --> K[start_optional_services]
    K --> L[Supervisor inicia<br/>postgresql]
    L --> M[Supervisor inicia<br/>stellar-core node]
    M --> N[stellar-core faz<br/>catchup + sync]
    N --> O[Supervisor inicia<br/>horizon]
    O --> P[Horizon inicia<br/>captive core]
    P --> Q[Captive core faz<br/>catchup + sync]
    Q --> R[Horizon: ingestion<br/>caught up ✅]
    R --> S[Sistema pronto<br/>:8000 respondendo]
    
    style R fill:#4caf50,color:white
    style S fill:#2196f3,color:white
```

---

## 10. Conclusão

### Resumo dos Dados de Armazenamento

| Componente | Tecnologia | Tamanho | Localização |
|---|---|---|---|
| Bucket List (Node) | Arquivos .xdr | **4.7 GB** | `/opt/stellar/core/buckets/` |
| Bucket List (Captive) | Arquivos .xdr | **5.4 GB** | `/opt/stellar/horizon/captive-core/captive-core/buckets/` |
| SQLite (Node) | SQLite | **62 MB** (com WAL) | `/opt/stellar/core/stellar.db` |
| SQLite (Captive) | SQLite | **33 MB** (com WAL) | `/opt/stellar/horizon/captive-core/stellar.db` |
| PostgreSQL (Horizon) | PostgreSQL | **~1.2 GB** | Volume Docker (`/opt/stellar/postgresql/data/`) |
| **Total** | | **~10-11 GB** | Volume Docker `stellar-data` |

### Por que 2 instâncias do Stellar Core?

O uso de **duas instâncias** do stellar-core (node + captive) é uma arquitetura deliberada do Horizon moderno:

1. **Node (PID 291):** Mantém o estado completo da rede, participa do consenso SCP, conecta-se a peers. É o "verificador" que garante que os dados estão corretos.

2. **Captive Core (PID 3985):** É uma instância **descartável** e **isolada** que o Horizon gerencia. Ela não participa do consenso — apenas faz catchup via history archives e envia metadados das transações para o Horizon via pipe (`fd:3`). Isso permite que o Horizon faça ingestão sem interferir no nó principal.

### Como o Horizon Sabe o que Está Acontecendo?

O Horizon se conecta ao Captive Core via:
1. **HTTP** (`STELLAR_CORE_URL=http://localhost:11726`) — para obter informações de ledger atual
2. **Metadata Stream** (`--metadata-output-stream fd:3`) — pipe para receber metadados de transações em tempo real
3. **SQLite Database** (`CAPTIVE_CORE_USE_DB=true`) — acesso direto ao banco do captive core

### Comandos Úteis

```bash
# Ver logs do stellar-core node
docker compose logs stellar-testnet | grep "stellar-core(node)"

# Ver logs do captive core
docker compose logs stellar-testnet | grep "stellar-core(horizon)"

# Ver logs do horizon
docker compose logs stellar-testnet | grep "horizon:"

# Ver status atual via API
curl -s http://localhost:8000 | jq '.core_latest_ledger, .history_latest_ledger'

# Listar peers conectados
curl -s http://localhost:11626/peers | jq '.outgoing_peers[] | {ip, port, lat}'

# Ver info do stellar-core node
curl -s http://localhost:11626/info | jq '.info.state, .info.ledger.num, .info.peers'
```

---

> **Relatório gerado em:** 15/07/2026  
> **Baseado no container:** stellar/quickstart:testing (testnet)  
> **Ledger no momento da coleta:** ~3,629,501
