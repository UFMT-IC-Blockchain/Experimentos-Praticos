# Análise de Sincronização do Stellar Testnet

**Data:** 2026-07-17
**Última atualização:** 2026-07-17 20:30h
**Container:** stellar-testnet (stellar/quickstart:testing)
**Rede:** Testnet ("Test SDF Network ; September 2015")
**Versão Core:** v27.1.0
**Versão Horizon:** devel

---

## 1. Arquitetura Geral do Container

O container usa **supervisord** para gerenciar múltiplos processos. O entrypoint é `/start` (bash script) que:

1. Copia configurações padrão para volumes persistentes (se primeira execução)
2. Inicializa PostgreSQL e cria banco `horizon`
3. Inicializa Stellar Core (new-db)
4. Inicializa Horizon (db init)
5. Para o PostgreSQL temporário
6. Executa `supervisord` que gerencia os serviços

### Serviços gerenciados pelo supervisor:

| Serviço | Binário | Porta | Função |
|---------|---------|-------|--------|
| **stellar-core (node)** | `/usr/bin/stellar-core --conf ...` | 11625 (P2P), 11626 (HTTP) | Consenso SCP, sincronização ledger, P2P |
| **stellar-core (captive core do Horizon)** | `/usr/bin/stellar-core --conf ... --metadata-output-stream fd:3` | 11725 (P2P), 11726 (HTTP) | Processo filho do Horizon para ingestão de dados |
| **Horizon** | `/usr/bin/stellar-horizon` | 8001 (HTTP), 6060 (admin) | API RESTful, ingestão dos dados do ledger no PostgreSQL |
| **PostgreSQL** | `/usr/lib/postgresql/14/bin/postgres` | 5432 | Banco de dados do Horizon |
| **nginx** | `/usr/sbin/nginx` | 8000 (público) | Proxy reverso: `/` -> Horizon, `/friendbot` -> externo, `/rpc` -> RPC |

### Portas expostas no host:
- `8000:8000` — nginx (proxy para Horizon)
- `11625:11625` — Core P2P (conexão com validadores)
- `11626:11626` — Core HTTP (admin/info)

---

## 2. Fluxo de Sincronização (Passo a Passo)

Após o container iniciar, o processo de sincronização segue estas etapas:

### Fase 1: Inicialização dos Serviços
1. Supervisord inicia `nginx` e `stellar-core` (node)
2. Core node começa a sincronizar do genesis — baixa **histórico** e **buckets** dos archives
3. Supervisord inicia `postgresql`
4. Supervisord inicia `horizon`
5. Horizon verifica se o Core node já alcançou ledger mínimo (`core_latest_ledger > 5`)

### Fase 2: Core Node — Catching Up
O Core node executa dois processos em paralelo:
- **Processo "node"** (porta 11626): Sincronização principal via P2P + archives
- **Processo "horizon"** (porta 11726): Instância captive core do Horizon

**Logs observados para o node:**
```
Catching up to ledger 3663423: downloading ledger files 247/247 (100%)
Download & apply checkpoints: num checkpoints left to apply:247 (0% done)
```

**Logs observados para o horizon (captive core):**
```
Joining SCP; Catching up to ledger 3647651:
  downloading and verifying buckets: 37/37 (100%)
  Applying buckets 100%
  Download & apply checkpoints: num checkpoints left to apply:1
```

### Fase 3: Captive Core do Horizon
O Horizon gerencia sua própria instância **captive core** (`ENABLE_CAPTIVE_CORE_INGESTION=true`). Esta instância:
- Usa config separada: `/opt/stellar/horizon/etc/stellar-captive-core.cfg`
- Porta HTTP própria: 11726 (loopback apenas)
- Porta P2P própria: 11725
- Banco SQLite próprio: `/opt/stellar/horizon/captive-core/stellar.db`
- Buckets próprios: `/opt/stellar/horizon/captive-core/captive-core/buckets/`

### Fase 4: Horizon Ingest
Quando o captive core alcança um ledger válido, o Horizon:
1. Lê metadados do ledger via pipe (`--metadata-output-stream fd:3`)
2. Processa transactions, operations, effects, accounts, etc.
3. Persiste no PostgreSQL (banco `horizon`)
4. Atualiza `ingest_latest_ledger` no endpoint `/`

---

## 3. Requisições Externas (Para Onde e o Quê)

### 3.1. History Archives (download de dados históricos)

**URLs base:**
- `https://history.stellar.org/prd/core-testnet/core_testnet_001`
- `https://history.stellar.org/prd/core-testnet/core_testnet_002`
- `https://history.stellar.org/prd/core-testnet/core_testnet_003`

**Arquivos baixados:**

| Tipo | Formato | Exemplo | Conteúdo |
|------|---------|---------|----------|
| Ledger headers | JSON | `history-00/37/a8/history-0037a87f.json` | Cabeçalhos de checkpoint (64 ledgers) |
| Transaction history | XDR | `transaction/00/37/a8/transactions-0037a87f.xdr` | Transações agrupadas |
| Buckets | XDR | `bucket-022e182f76b419ae6e03ee5c99ac10cba115ced44e8329e17bf8fb9ea093e17a.xdr` | Estado completo da ledger (accounts, trustlines, offers, etc.) |
| Bucket indexes | Index | `bucket-....index` | Índices para busca nos buckets |
| Results | XDR | `results-....xdr` | Resultados das transações |
| SCVal | XDR | `scval-....xdr` | Valores Soroban (contratos inteligentes) |

### 3.2. P2P (Consenso em tempo real)

**Destinos:**
- `core-testnet1.stellar.org:11625`
- `core-testnet2.stellar.org:11625`
- `core-testnet3.stellar.org:11625`

**Protocolo:** Stellar SCP (SCP — Stellar Consensus Protocol) sobre TCP porta 11625

**Dados trocados:**
- Envelopes SCP (nomination, ballot, externalize)
- Transações do mempool
- Mensagens de peer discovery (ID, versão, rede)

### 3.3. Friendbot (apenas quando habilitado)

**URL:** `https://friendbot.stellar.org`

**Função:** Proxiado pelo nginx em `/friendbot` — utilizado para criar contas de teste na testnet.

### 3.4. Monitoramento interno (sem saída externa)
- `curl http://localhost:11726/info` — status do captive core (Horizon)
- `curl http://localhost:11626/info` — status do core node
- `curl http://localhost:8001` — health check do Horizon

---

## 4. Carga no Banco de Dados

### 4.1. PostgreSQL (Horizon — dados processados/estruturados)

**Tamanho total:** ~39MB (ainda em sincronização)

**Tabelas principais e seus tamanhos:**

| Tabela | Tamanho | Conteúdo |
|--------|---------|----------|
| `accounts_signers` | 1427 MB | Signers de contas (a maior tabela — cada multi-sig aumenta) |
| `accounts` | 872 MB | Estado atual de todas as contas |
| `history_transactions` | 590 MB | Histórico de transações processadas |
| `trust_lines` | 279 MB | Trustlines (confiança em ativos) |
| `accounts_data` | 220 MB | Data entries das contas |
| `history_operations` | 182 MB | Operações individuais dentro de transações |
| `offers` | 34 MB | Ofertas vivas (order book) |
| `history_effects` | 33 MB | Efeitos das operações |
| `exp_asset_stats` | 34 MB | Estatísticas de ativos |
| `history_ledgers` | 17 MB | Cabeçalhos dos ledgers |

**Nota:** As tabelas de histórico (`history_*`) armazenam dados imutáveis para consulta via API. As tabelas "vivas" (`accounts`, `offers`, `trust_lines`) refletem o estado atual.

### 4.2. SQLite (Core Node)

**Arquivos em `/opt/stellar/core/`:**
- `stellar.db` (21 MB) — Dados do ledger do Core node
- `stellar-misc.db` (0.2 MB) + WAL (41 MB) — Dados miscelânea (provavelmente quorum state, peers, etc.)
- `buckets/` (4.5 GB) — Buckets XDR do estado completo da ledger

### 4.3. SQLite (Captive Core do Horizon)

**Arquivos em `/opt/stellar/horizon/captive-core/`:**
- `stellar.db` (21 MB) — Ledger do captive core
- `stellar-misc.db` (0.06 MB) + WAL (2.8 MB) — Misc
- `bucket-cache/` (4 KB) — Cache de buckets

### 4.4. Armazenamento total
```
/opt/stellar/            = 14 GB
├── core/                = 4.6 GB  (node principal + buckets)
├── horizon/captive-core = 4.6 GB  (captive core + buckets)
└── postgresql/          = 39 MB   (PostgreSQL data)
```

---

## 5. Pipeline de Processamento: Fluxo dos Dados

```
History Archives (SDF)
  https://history.stellar.org/prd/core-testnet/
         │
         ├────────────────────────────────────────┐
         ▼                                        ▼
  ┌──────────────┐                        ┌──────────────┐
  │ Core Node    │                        │ Captive Core │
  │ (main)       │                        │ (Horizon)    │
  │              │                        │              │
  │ Baixa:       │                        │ Baixa:       │
  │ - ledgers    │                        │ - buckets    │
  │ - buckets    │                        │ - ledgers    │
  │ - txs        │                        │              │
  │              │                        │              │
  │ Porta:       │                        │ Porta:       │
  │  11625 (P2P) │                        │  11725 (P2P) │
  │  11626 (HTTP)│                        │  11726 (HTTP)│
  └──────┬───────┘                        └──────┬────────┘
         │                                       │
         │ P2P consensus (SCP)                   │ metadata pipe
         │                                       ▼
         │                               ┌──────────────┐
         │                               │ Horizon       │
         │                               │              │
         │                               │ Lê metadados │
         │                               │ via fd:3     │
         │                               │              │
         │                               │ Processa:    │
         │                               │ - txs        │
         │                               │ - operations │
         │                               │ - effects    │
         │                               │ - accounts   │
         │                               └──────┬───────┘
         │                                       │
         │                                       ▼
         │                               ┌──────────────┐
         │                               │ PostgreSQL   │
         │                               │ (banco       │
         │                               │  horizon)    │
         │                               │              │
         │                               │ 33 tabelas   │
         │                               │ ~39 MB       │
         │                               └──────────────┘
         │
         ▼
  ┌──────────────┐
  │ SQLite local │
  │ (core node)  │
  │              │
  │ stellar.db   │
  │ 21 MB        │
  │ buckets 4.5GB│
  └──────────────┘
```

### 5.1. O que vai para o **Core Node** (SQLite)
- Ledger headers e sequence numbers
- Buckets: estado completo do ledger (accounts, trustlines, offers, data, signers)
- Transações e resultados
- Informações de quorum/SCP
- Configuração de validadores

### 5.2. O que vai para o **Captive Core** (SQLite)
- Buckets necessários para reconstruir estado
- Ledgers para processamento
- **Não participa do consenso P2P** (apenas para ingestão)
- Gerenciado pelo Horizon

### 5.3. O que vai para o **Horizon** (PostgreSQL)
- Dados processados e estruturados em 33 tabelas:
  - **Accounts** (`accounts`, `accounts_signers`, `accounts_data`)
  - **Transactions** (`history_transactions`, `history_transaction_participants`)
  - **Operations** (`history_operations`, `history_operation_participants`)
  - **Effects** (`history_effects`) — cada operação gera N efeitos
  - **Assets** (`history_assets`, `exp_asset_stats`, `asset_contracts`)
  - **Trades** (`history_trades`, `history_trades_60000`)
  - **Claimable Balances** (`claimable_balances`, `claimable_balance_claimants`)
  - **Liquidity Pools** (`liquidity_pools`, `history_liquidity_pools`)
  - **Offers** (`offers`)
  - **Fee Stats** (embutido na API)
  - **Contract data** (Soroban: `contract_asset_balances`, `contract_asset_stats`)
  - **Filters** (`account_filter_rules`, `asset_filter_rules`)
  - **Migrações** (`gorp_migrations`) — controle de schema
  - **Key-value** (`key_value_store`) — configuração interna

---

## 6. Diferenças entre os dois Core Processes

| Característica | Core Node (PID 118) | Captive Core (PID 3929) |
|---------------|---------------------|------------------------|
| **Config** | `/opt/stellar/core/etc/stellar-core.cfg` | `/opt/stellar/horizon/etc/stellar-captive-core.cfg` |
| **Banco** | SQLite `/opt/stellar/core/stellar.db` | SQLite `/opt/stellar/horizon/captive-core/stellar.db` |
| **Buckets** | `/opt/stellar/core/buckets/` (4.5 GB) | `/opt/stellar/horizon/captive-core/captive-core/buckets/` (mesmo tamanho) |
| **P2P port** | 11625 | 11725 |
| **HTTP port** | 11626 | 11726 |
| **Participa do SCP?** | Sim | Não |
| **Output metadata** | Normal | Pipe fd:3 para o Horizon |
| **Iniciado por** | supervisord (service) | Horizon (fork/exec) |
| **Propósito** | Consenso + sync | Fornecer dados de ledger para ingestão |

---

## 7. Observações sobre o Comportamento de Sincronização

1. **Duplicação de dados**: O Core node e o Captive core do Horizon baixam buckets separadamente (~4.5 GB cada). Ambos vêm dos mesmos history archives da SDF.

2. **Estratégia de catchup**: O Core node usa `CATCHUP_RECENT=100` (configurado no stellar-core.cfg), o que significa que ele tenta alcançar os últimos 100 ledgers antes de entrar no modo de consenso.

3. **Checkpoints**: A cada 64 ledgers, um checkpoint é gerado. `CHECKPOINT_FREQUENCY=64` no Horizon.

4. **Ingestão**: `INGEST_DISABLE_STATE_VERIFICATION=True` — a verificação de estado é pulada para acelerar a sincronização inicial.

5. **State verification**: `ENABLE_CAPTIVE_CORE_INGESTION=true` + `CAPTIVE_CORE_USE_DB=true` — o Horizon usa captive core com banco SQLite para reconstruir estado, em vez de chamar a API HTTP do core node.

6. **Rate limit**: `PER_HOUR_RATE_LIMIT=72000` — 72.000 requisições por hora no Horizon.

7. **Latência observada**: O sistema levou ~3 minutos para o captive core alcançar o ledger alvo e o Horizon começar a ingerir dados.

---

## 8. Endpoints da API Horizon (expostos via nginx na porta 8000)

| Rota | Descrição |
|------|-----------|
| `/` | Root — informações do ledger e links HATEOAS |
| `/accounts` | Lista contas |
| `/accounts/{id}` | Detalhes de conta |
| `/transactions` | Histórico de transações |
| `/operations` | Operações |
| `/effects` | Efeitos |
| `/ledgers` | Ledgers |
| `/assets` | Ativos |
| `/trades` | Trades |
| `/offers` | Ofertas |
| `/payments` | Pagamentos |
| `/claimable_balances` | Saldos reclamáveis |
| `/liquidity_pools` | Pools de liquidez |
| `/fee_stats` | Estatísticas de fees |
| `/order_book` | Order book |
| `/paths/strict-receive` | Path finding |
| `/paths/strict-send` | Path finding |

---

## 9. Configurações Chave

**Horizon (`horizon.env`):**
```bash
DATABASE_URL="postgres://stellar:<pass>@localhost/horizon"
STELLAR_CORE_URL="http://localhost:11726"
ENABLE_CAPTIVE_CORE_INGESTION="true"
CAPTIVE_CORE_USE_DB=true
INGEST="true"
CHECKPOINT_FREQUENCY=64
INGEST_DISABLE_STATE_VERIFICATION=True
HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-testnet/core_testnet_001"
```

**Core Node (`stellar-core.cfg`):**
```ini
HTTP_PORT=11626
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/core/stellar.db"
CATCHUP_RECENT=100
```

**Captive Core (`stellar-captive-core.cfg`):**
```ini
HTTP_PORT=11726
PEER_PORT=11725
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/horizon/captive-core/stellar.db"
```

---

## 10. Análise Quantitativa do Estado Sincronizado

### 10.1. Conteúdo dos Buckets (estado completo da rede)

Dados obtidos das métricas do stellar-core (`/metrics`) durante a execução:

| Tipo de Entrada | Quantidade | Tamanho Total (bytes) | % do Estado |
|----------------|------------|----------------------|------------|
| PERSISTENT_CONTRACT_DATA | 4.360.649 | 740.016.048 | 40,2% |
| ACCOUNT | 2.952.227 | 374.514.724 | 20,3% |
| CONTRACT_CODE | 25.168 | 326.714.560 | 17,7% |
| TTL (Time-To-Live) | 4.552.345 | 217.381.504 | 11,8% |
| TRUSTLINE | 335.370 | 45.534.520 | 2,5% |
| DATA (account data) | 340.684 | 49.321.276 | 2,7% |
| OFFER | 62.150 | 8.689.832 | 0,5% |
| TEMPORARY_CONTRACT_DATA | 167.877 | 24.684.924 | 1,3% |
| CLAIMABLE_BALANCE | 9.242 | 2.406.644 | 0,1% |
| LIQUIDITY_POOL | 2.687 | 422.480 | 0,02% |
| CONFIG_SETTING | 55 | 9.128 | <0,01% |
| **Total** | **~13.808.454** | **~1.840.929.876** | **100%** |

**Tamanho total em arquivo:** ~4,4 GB (compactado/diferenciado)
**Tamanho total descompactado:** ~1,84 GB

### 10.2. Buckets por Nível (Merge Levels)

O sistema de buckets do stellar-core organiza os buckets em níveis (0-6):

- **Level 0 (base):** ~677 merges — buckets pequenos com dados recentes
- **Level 1:** ~2.797 merges
- **Level 2:** ~758 merges
- **Level 3:** ~208 merges
- **Level 4:** ~63 merges
- **Level 5:** ~18 merges
- **Level 6 (snap):** ~4 merges — buckets grandes com snapshots completos

**Top 5 maiores buckets (arquivos XDR nao-compactados):**

| Arquivo | Tamanho |
|---------|---------|
| bucket-ff26b4f5...7efd.xdr | 785 MB |
| bucket-eb7625ce...4b72.xdr | 610 MB |
| bucket-d8522ede...2d730.xdr | 600 MB |
| bucket-8a27deda...b125.xdr | 452 MB |
| bucket-b2a2c09a...d09b.xdr | 355 MB |

### 10.3. Armazenamento SQLite

**Core Node (SQLite WAL pesado):**
| Arquivo | Tamanho |
|---------|---------|
| stellar.db | 21 MB (dados compactados) |
| stellar.db-wal | 44 MB (Write-Ahead Log — writes ativos) |
| stellar.db-shm | 96 KB (Shared Memory) |
| stellar-misc.db | 208 KB |
| stellar-misc.db-wal | 40 MB |

**Captive Core (SQLite idêntico em estrutura):**
| Arquivo | Tamanho |
|---------|---------|
| stellar.db | 21 MB |
| stellar.db-wal | 40 MB |
| stellar-misc.db | 64 KB |
| stellar-misc.db-wal | 8,1 MB |

### 10.4. Banco PostgreSQL (Horizon)

**Database total:** 3.955 MB (dados + índices)
**WAL:** 417 MB (arquivos de 16 MB cada)

**Tamanhos reais por tabela (incluindo índices e TOAST):**

| Tabela | Total (dados + índices) | Dados (heap) | Índices/TOAST | % do DB |
|--------|------------------------|-------------|---------------|---------|
| accounts_signers | 1.428 MB | 429 MB | 999 MB | 36,1% |
| accounts | 873 MB | 499 MB | 374 MB | 22,1% |
| history_transactions | 679 MB | 357 MB | 322 MB | 17,2% |
| trust_lines | 279 MB | 108 MB | 171 MB | 7,1% |
| accounts_data | 220 MB | 95 MB | 126 MB | 5,6% |
| history_operations | 210 MB | 190 MB | 20 MB | 5,3% |
| history_operation_participants | 48 MB | 21 MB | 27 MB | 1,2% |
| history_transaction_participants | 38 MB | 17 MB | 21 MB | 1,0% |
| history_effects | 37 MB | 26 MB | 11 MB | 0,9% |
| demais (24 tabelas) | ~165 MB | ~90 MB | ~75 MB | 4,2% |

**Contagem de registros processados pelo Horizon:**
- **Accounts (contas):** 2.909.585
- **Transactions (transações):** 236.368
- **Operations (operações):** 361.670
- **Ledgers ingeridos:** 21.593 (range: 3.629.312 a 3.650.904)

---

## 11. Pipeline de Processamento Detalhado — O Caminho dos Dados

```
                        HISTORY ARCHIVES (SDF)
                     https://history.stellar.org/
                              |
               ┌──────────────┴──────────────┐
               ▼                              ▼
    ┌──────────────────┐          ┌──────────────────┐
    │   CORE NODE      │          │  CAPTIVE CORE    │
    │  (PID 118)       │          │  (PID 3929)      │
    │                  │          │                  │
    │ 1. Baixa         │          │ 1. Baixa         │
    │    ledger files  │          │    ledger files  │
    │    (JSON)        │          │    (JSON)        │
    │                  │          │                  │
    │ 2. Baixa         │          │ 2. Baixa         │
    │    buckets (XDR) │          │    buckets (XDR) │
    │    via HTTP      │          │    via HTTP      │
    │                  │          │                  │
    │ 3. Verifica      │          │ 3. Verifica      │
    │    hashes SHA256 │          │    hashes SHA256 │
    │                  │          │                  │
    │ 4. Apply         │          │ 4. Apply         │
    │    checkpoints   │          │    checkpoints   │
    │    (replay txs)  │          │    (replay txs)  │
    │                  │          │                  │
    │ 5. SCP Consensus │          │ 5. (NO SCP)      │
    │    (P2P)         │          │    só replay     │
    └──────┬───────────┘          └────────┬─────────┘
           │                               │
           │ P2P: 11625                    │ Pipe: fd:3
           │ HTTP: 11626                   │ (metadata)
           │                               ▼
           │                     ┌──────────────────┐
           │                     │    HORIZON       │
           │                     │  (PID 168)       │
           │                     │                  │
           │                     │ Lê metadados do  │
           │                     │ captive core via │
           │                     │ pipe (stdout     │
           │                     │ ledger metadata) │
           │                     │                  │
           │                     │ Para cada ledger:│
           │                     │  - Meta (header) │
           │                     │  - TxSet         │
           │                     │  - Tx processing │
           │                     │  - Operations    │
           │                     │  - Effects       │
           │                     │  - Account       │
           │                     │    changes       │
           │                     │  - Trades        │
           │                     │  - etc.          │
           │                     └────────┬─────────┘
           │                              │
           │                              ▼
           │                     ┌──────────────────┐
           │                     │   PostgreSQL     │
           │                     │  Porta 5432      │
           │                     │                  │
           │                     │ 33 tabelas       │
           │                     │ 3.955 MB         │
           │                     └──────────────────┘
           │
           ▼
    ┌──────────────────┐
    │    SQLite        │
    │  stellar.db      │
    │  21 MB + WAL     │
    │                  │
    │ buckets/         │
    │  4.4 GB (79 .xdr)│
    └──────────────────┘
```

### 11.1. Detalhamento: O que cada componente processa

**Core Node (stellar-core PID 118):**
- **Download de checkpoints:** Baixa arquivos JSON de ledger headers e transações do history archive
- **Download de buckets:** Baixa arquivos XDR com snapshots de estado (accounts, offers, trustlines, contract data)
- **Verificação criptográfica:** SHA256 de cada bucket, verificação de assinaturas SCP
- **Merge de buckets:** Combina buckets de níveis inferiores em superiores (níveis 0 a 6)
- **Replay de transações:** Aplica transações dos checkpoints para avançar o estado
- **SCP Consensus:** Participa do protocolo de consenso com validadores SDF via P2P

**Captive Core (outro stellar-core, filho do Horizon):**
- **Mesmas etapas do Core Node**, exceto que NÃO participa do SCP
- **Propósito único:** Fornecer metadata de ledger para o Horizon via pipe (`--metadata-output-stream fd:3`)
- **Portas separadas:** 11725 (P2P, sem peers), 11726 (HTTP, loopback)

**Horizon (stellar-horizon PID 168):**
- **Recebe metadata do captive core** via pipe (stdout do processo)
- **Para cada novo ledger meta recebido:**
  1. Insere `history_ledgers` (header, timestamp, hash)
  2. Insere `history_transactions` + participantes
  3. Processa cada operação → `history_operations` + participantes
  4. Gera efeitos → `history_effects`
  5. Atualiza estado atual: `accounts`, `accounts_signers`, `accounts_data`, `trust_lines`, `offers`
  6. Processa trades → `history_trades`
  7. Processa claimable balances → `claimable_balances`, `claimable_balance_claimants`
  8. Processa liquidity pools → `liquidity_pools`
  9. Processa contratos Soroban → `contract_asset_balances`, `contract_asset_stats`, `asset_contracts`
  10. Atualiza `exp_asset_stats`

### 11.2. Por que dois core processes?

O Horizon usa **Captive Core Ingestion** (`ENABLE_CAPTIVE_CORE_INGESTION=true`) para:
1. **Isolamento**: A ingestão não interfere com o consenso do core principal
2. **Performance**: O captive core pode ser configurado independentemente (portas, banco, buckets)
3. **Snapshot consistente**: O captive core fornece um ponto de vista consistente dos dados

**Custo:** Duplicação de armazenamento (~4,6 GB de buckets cada) e processamento redundante.

---

## 12. Métricas de Rede e Processamento (do Core Node)

### 12.1. SCP (Consenso)

| Métrica | Valor |
|---------|-------|
| SCP envelopes recebidos | 4.713 |
| SCP envelopes assinados | 467 |
| SCP envelopes com validação OK | 4.298 |
| SCP nominate timeouts | 115 |
| SCP prepare timeouts | 115 |
| Ballot blocked on txset | 115 |

### 12.2. Overlay (P2P)

| Métrica | Valor |
|---------|-------|
| Bytes lidos (rede) | 4,56 MB |
| Bytes escritos (rede) | 1,90 MB |
| Mensagens lidas | 7.134 |
| Mensagens escritas | 5.012 |
| Conexões autenticadas | 3 |
| Conexões estabelecidas | 225 |
| Conexões rejeitadas | 221 |
| SCP messages broadcast | 4.063 |
| Flood unique received | 906.252 |

### 12.3. History Archive Downloads

| Métrica | Valor |
|---------|-------|
| Throughput total (bytes) | 18.082.855 (~18 MB) |
| History check success | 3 |
| Ledger check success | 3 |
| Bucket batch add time | 4.822 calls |
| Objetos adicionados aos buckets | 158.534 |

### 12.4. Ledger Processing

| Métrica | Valor |
|---------|-------|
| Ledgers closed | 4.822 |
| Ledger apply successes | 39.129 |
| Ledger apply failures | 7.742 |
| Transações aplicadas | 46.871 |
| Operações aplicadas | 71.502 |
| Soroban successes | 30.852 |
| Soroban failures | 356 |
| Média de txs/ledger | ~9,7 |
| Média de ops/ledger | ~15,0 |

### 12.5. Soroban (Contratos Inteligentes)

| Métrica | Valor |
|---------|-------|
| Host functions executadas | 31.194 |
| CPU instructions (total) | ~261 bilhões |
| Memória utilizada | ~81,9 GB (total acumulado) |
| Entradas de código contrato em memória | 4.668 |
| Tamanho código contrato em memória | ~2,37 GB |
| Entradas de data contrato em memória | 1.311.996 |
| Tamanho data contrato em memória | ~299 MB |
| Entradas de código compilado | 4.668 |
| Tempo total compilação | 77 unidades |
| Read entries | 165.732 |
| Write entries | 52.866 |

---

## 13. Análise do Gap de Sincronização

Durante a execução observou-se uma diferença consistente entre o Core Node e o Captive Core:

| Instância | Ledger Atual | Progresso | Ledgers restantes |
|-----------|-------------|-----------|------------------|
| Core Node | 3.653.467 | ~70,8% | ~157 checkpoints |
| Captive Core | 3.651.297 | ~64,3% | ~191 checkpoints |
| Horizon (ingest) | 3.651.291 | — | trailing captive |

**Gap Core vs Captive:** 2.170 ledgers
**Gap Captive vs Horizon:** 6 ledgers (latência normal de processamento)

O Core node está cerca de **2.100 ledgers à frente** do captive core porque:
1. O Core node iniciou primeiro (PID 118, started 00:22:42)
2. O Captive core iniciou depois (PID 3929, started 00:26:14) — ~3,5 minutos depois
3. Ambos baixam buckets independentemente (mesma source)
4. O Horizon precisa esperar o captive core alcançar antes de ingerir novos dados

---

## 14. Topologia de Rede Completa

```
HOST: localhost
├── :8000 → nginx (proxy reverso)
│   ├── / → Horizon (127.0.0.1:8001)
│   ├── /friendbot → friendbot.stellar.org (externo)
│   └── /rpc → Stellar RPC (127.0.0.1:8003) [não ativo neste setup]
│
├── :11625 → Core Node P2P → core-testnet{1,2,3}.stellar.org:11625
├── :11626 → Core Node HTTP (admin/info)
│
└── (interno)
    ├── 127.0.0.1:11725 → Captive Core P2P (sem peers externos)
    ├── 127.0.0.1:11726 → Captive Core HTTP (Horizon consome)
    ├── 127.0.0.1:5432 → PostgreSQL (Horizon consome)
    ├── 127.0.0.1:8001 → Horizon API (nginx + captive core consumer)
    ├── 127.0.0.1:6060 → Horizon Admin
    ├── 127.0.0.1:9001 → Supervisord HTTP
    └── 127.0.0.11:44005 → Docker DNS

EXTERNO:
├── history.stellar.org (HTTPS) — downloads de archives
│   ├── /prd/core-testnet/core_testnet_001/
│   ├── /prd/core-testnet/core_testnet_002/
│   └── /prd/core-testnet/core_testnet_003/
├── core-testnet1.stellar.org:11625 (P2P SCP)
├── core-testnet2.stellar.org:11625 (P2P SCP)
├── core-testnet3.stellar.org:11625 (P2P SCP)
└── friendbot.stellar.org:443 (HTTPS) — criação de contas
```

---

## 15. Fluxo de Dados: Request → Response (API Horizon)

```
CLIENTE                         NGINX                   HORIZON                 POSTGRESQL
  │                               │                        │                       │
  │── GET /accounts/G... ──────► │                        │                       │
  │                               │── GET /... ──────────► │                       │
  │                               │                        │── SELECT accounts ──► │
  │                               │                        │── SELECT signers ────► │
  │                               │                        │◄── rows ───────────── │
  │                               │◄── JSON ───────────── │                       │
  │◄── JSON Response ─────────── │                        │                       │
```

Os dados servidos pela API Horizon vêm das tabelas do PostgreSQL que são populadas durante a ingestão.

---

## 16. Observações Finais

1. **Soroban domina o estado**: Contratos inteligentes (Soroban) representam ~58% do estado total (PERSISTENT_CONTRACT_DATA + CONTRACT_CODE + TTL). A testnet tem forte atividade de contratos.

2. **Duplicação intencional**: Os dois core processes baixam buckets separadamente (~9 GB total entre core node + captive core). Isso é o custo do isolamento da ingestão.

3. **SQLite WAL grande**: Ambos os SQLites têm WALs de ~40-44 MB, indicando escritas intensas durante o catchup. Isso normaliza após atingir o estado estável.

4. **PostgreSQL cresce rápido**: Em ~30 minutos de catchup, o banco foi de 0 para ~4 GB. A tabela `accounts_signers` é a maior (1.4 GB com índices) devido à natureza multi-sig do Stellar.

5. **3 validadores SDF**: A testnet usa 3 validadores da SDF com quorum seguro (fail_at=2, agreement=3). A rede tem 4 nós no total.

6. **P2P inbound limitado**: Das 225 tentativas de conexão de saída, 221 foram descartadas, sugerindo que o core node aceita apenas as 3 conexões autenticadas dos validadores.

7. **Processing rate**: ~9,7 transações e ~15 operações por ledger em média, com picos de até 26 transações e 89 operações.

---

## 17. Resultado Final da Sincronização

A sincronização completa foi atingida após aproximadamente **30-40 minutos** de execução do container.

### Estado final:

| Instância | Ledger Final | Estado |
|-----------|-------------|--------|
| Core Node | 3.663.788 | Synced! |
| Captive Core | 3.663.789 | Synced! |
| Horizon (ingest) | 3.663.788 | catch up concluído |
| Horizon (history) | 3.663.788 | catch up concluído |

### Observações do processo de sincronização:

1. O Core node baixou e aplicou checkpoints em lotes de 64 ledgers cada, começando do ledger ~3.629.312
2. Durante o catchup, o Core node foi atualizando seu target a cada ~5 checkpoints aplicados (ex: de 3.663.423 para 3.663.743)
3. O Captive core manteve-se consistentemente atrás do Core node durante todo o processo (~2.000-3.000 ledgers de diferença)
4. O Horizon manteve-se ~6 ledgers atrás do Captive core (latência de processamento/ingestão)
5. Após atingir o estado "Synced!", todos os componentes passam a operar em modo de tempo real, processando novos ledgers conforme são fechados pela rede Stellar testnet (~5 segundos por ledger)

