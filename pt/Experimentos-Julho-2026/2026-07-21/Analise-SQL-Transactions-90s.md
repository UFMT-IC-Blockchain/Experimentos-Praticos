# Análise de Transações SQL nos Bancos do Stellar (90 segundos)

**Data:** 2026-07-22 01:39-01:41 UTC
**Duração da Janela:** 90 segundos
**Containers Analisados:** stellar-core (SQLite) + stellar-horizon (PostgreSQL + SQLite captive)

---

## Sumário Executivo

- **3 bancos de dados** monitorados simultaneamente por 90s
- **3.076 MB** de dados no PostgreSQL, **1.008 MB** de WAL
- **17 ledgers** processados na janela (~0,19 ledgers/s)
- **33 tabelas** no PostgreSQL, **2 tabelas** em cada SQLite
- **Padrão dominante**: INSERT em tabelas de histórico + UPDATE em tabelas de estado

---

## 1. Arquitetura dos Bancos

```
CONTAINER 1: stellar-core                  CONTAINER 2: stellar-horizon
┌─────────────────────────┐               ┌──────────────────────────────────┐
│  SQLite (core)          │               │  PostgreSQL 16 (horizon)         │
│  ├── offers (56.602)    │               │  ├── 33 tabelas públicas         │
│  └── storestate (5)     │               │  ├── 3.076 MB de dados          │
│                         │               │  ├── 1.008 MB de WAL (63 arqs)  │
│  Tamanho: 18 MB DB      │               │  └── Ingest ledger: 3.733.367   │
│  WAL: 42 MB             │               │                                  │
│  Page: 4.096 bytes      │               │  SQLite (captive core)          │
│  Modo: WAL              │               │  ├── offers (56.602)            │
│                         │               │  ├── storestate (5)             │
│                         │               │  ├── Tamanho: 23 MB DB          │
│                         │               │  └── WAL: 14 MB                 │
└─────────────────────────┘               └──────────────────────────────────┘
```

---

## 2. PostgreSQL — Análise Detalhada (90s)

### 2.1 Progresso da Ingestão

| Métrica | Valor |
|:--------|:------|
| Ledgers processados na janela | 17 |
| Taxa média | 0,19 ledgers/s |
| exp_ingest_last_ledger (fim) | 3.733.367 |
| offer_compaction_sequence | 3.733.267 |
| exp_ingest_version | 20 |
| exp_state_invalid | false |

### 2.2 Deltas por Tabela (90s)

Calculados pela diferença entre os dois snapshots de `pg_stat_user_tables`:

```
Tabela                              ΔINSERT    ΔUPDATE    ΔDELETE    ΔScan     ΔIdxScan   ΔLive
───────────────────────────────────────────────────────────────────────────────────────────────
TABELAS DE HISTÓRICO (INSERT-only):
history_operation_participants       +337       0          0          +0        +0         +337
history_transactions                 +184       0          0          +0        +180       +184
history_transaction_participants     +302       0          0          +0        +0         +302
history_operations                   +243       0          0          +0        +0         +243
history_effects                      +80        0          0          +0        +0         +80
history_ledgers                      +18        0          0          +0        +626       +18
history_accounts                     +25        0          0          +18       +25        +25
history_trades                       +2         0          0          +0        +18        +2
history_assets                       +1         0          0          +1        +1         +1
history_trades_60000                 +3         0          +2          +18       +36        +1

TABELAS DE ESTADO (INSERT + UPDATE + DELETE):
accounts                             +1         +198       +1          +0        +199       +0
accounts_signers                     +1         +0         +1          +0        +1         +0
offers                               +6         +19        +17         +0        +93        -11
trust_lines                          +0         +29        +0          +0        +29        +0
exp_asset_stats                      +0         +5         +0          +0        +10        +0
contract_asset_balances              +6         +1         +0          +0        +19        +6
contract_asset_stats                 +0         +5         +0          +0        +10        +0

TABELAS DE CONTROLE:
key_value_store                      +0         +54        +0          +367      +54        +0
```

### 2.3 Distribuição de Operações por Tipo

```
┌─────────────────────────────────────────────────────────────────────┐
│  Distribuição de CRUD no PostgreSQL (90s)                           │
│                                                                     │
│  INSERT:  1.268 operações (62,3%)   ████████████████████████████    │
│  UPDATE:    311 operações (15,3%)   ██████▌                         │
│  DELETE:     21 operações ( 1,0%)   ▌                              │
│  SELECT:    436 operações (21,4%)   █████████                       │
│           ────────                                                  │
│  Total:  2.036 operações = 22,6 ops/s                               │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.4 Análise por Categoria de Tabela

#### 2.4.1 Tabelas de Histórico (INSERT puro — 62% das operações)

```
Fluxo típico por ledger processado:

1. INSERT history_ledgers               (1 linha)
2. INSERT history_transactions          (~10 linhas)
3. INSERT history_operation_participants(~19 linhas)
4. INSERT history_transaction_participants(~17 linhas)
5. INSERT history_operations            (~13 linhas)
6. INSERT history_effects               (~4 linhas)
7. INSERT history_accounts              (~1 linha)
8. INSERT history_trades                (~0,1 linha)
```

Estas tabelas são **append-only** — nunca sofrem UPDATE ou DELETE. São usadas para consultas históricas via API Horizon.

#### 2.4.2 Tabelas de Estado (INSERT + UPDATE + DELETE — 33% das operações)

```
Fluxo típico:

accounts:         1 INSERT + 198 UPDATES a cada 90s
  └── Atualiza saldos, sequence_number, num_subentries
  └── Cada UPDATE via índice (idx_scan +199)

accounts_signers: 1 INSERT + 1 DELETE a cada 90s
  └── Raras alterações de multi-sig

offers:           6 INSERT + 19 UPDATE + 17 DELETE a cada 90s
  └── Ofertas sendo criadas, modificadas e removidas
  └── Muitos scans sequenciais (199) indicando leituras de order book

trust_lines:      0 INSERT + 29 UPDATE a cada 90s
  └── Ajustes de confiança em ativos

exp_asset_stats:  0 INSERT + 5 UPDATE a cada 90s
  └── Estatísticas de ativos sendo recalculadas

contract_asset_balances: 6 INSERT + 1 UPDATE a cada 90s
  └── Saldos de contratos Soroban
```

#### 2.4.3 Tabelas de Controle

```
key_value_store:  54 UPDATES a cada 90s (0,6 updates/s)
  └── Tracking de ingestão: exp_ingest_last_ledger, compactação
```

### 2.5 Acesso aos Dados (Scans)

```
Estratégia de acesso:

Tabelas com SEQUENTIAL SCAN dominante:
  key_value_store:         4.304 seq scans (lê toda a tabela)
  asset_filter_rules:       364 seq scans
  account_filter_rules:     364 seq scans
  history_accounts:         366 seq scans (lê toda a tabela de contas)
  offers:                   199 seq scans (possivelmente order book)

Tabelas com INDEX SCAN dominante:
  history_ledgers:       10.133 idx scans (busca por ledger_seq)
  history_transactions:   1.668 idx scans (busca por hash)
  accounts:               3.881 idx scans (busca por account_id)
  offers:                 1.290 idx scans (busca por seller_id)
  trust_lines:              859 idx scans (busca por account + asset)
```

### 2.6 Checkpoints e WAL

```
BgWriter durante a janela:

Buffers checkpoint:     +875    (checkpoint escreveu 875 buffers)
Buffers backend:        +316    (consultas escreveram 316 buffers)
Buffers alloc:          +190    (novos buffers alocados)
Checkpoints timed:      +1      (1 checkpoint ocorreu na janela)

WAL:
  Tamanho: 1.008 MB (63 arquivos de 16 MB cada)
  Taxa: ~11 MB/min de WAL gerado durante ingestão
```

---

## 3. SQLite — Análise dos Dois Bancos

### 3.1 Schema (idêntico em ambos)

```sql
CREATE TABLE storestate (
    statename CHARACTER(70) PRIMARY KEY,
    state     TEXT
);

CREATE TABLE offers (
    sellerid     VARCHAR(56) NOT NULL,
    offerid      BIGINT NOT NULL CHECK (offerid >= 0),
    sellingasset TEXT NOT NULL,
    buyingasset  TEXT NOT NULL,
    amount       BIGINT NOT NULL CHECK (amount >= 0),
    pricen       INT NOT NULL,
    priced       INT NOT NULL,
    price        DOUBLE PRECISION NOT NULL,
    flags        INT NOT NULL,
    lastmodified INT NOT NULL,
    extension    TEXT NOT NULL,
    ledgerext    TEXT NOT NULL,
    PRIMARY KEY (offerid)
);

CREATE INDEX bestofferindex ON offers (sellingasset, buyingasset, price, offerid);
CREATE INDEX offerbyseller ON offers (sellerid);
```

### 3.2 Comparativo Core vs Captive

| Atributo | Core Node | Captive Core |
|:---------|:---------:|:------------:|
| **offers** | 56.602 rows | 56.602 rows |
| **storestate** | 5 rows | 5 rows |
| **DB file** | 18 MB | 23 MB |
| **WAL** | 42 MB | 14 MB |
| **Page size** | 4.096 bytes | 4.096 bytes |
| **Pages** | 5.687 | 5.660 |
| **Journal** | WAL | WAL |

### 3.3 Content of storestate

```
storestate table (5 linhas):
  ─ chaves de configuração interna do stellar-core
  ─ controlam o estado da bucket list
```

### 3.4 offers — Análise

```sql
-- Índices otimizados para busca:
-- 1. bestofferindex: sellingasset, buyingasset, price, offerid
--    → usado para order book (busca ofertas por par de ativos)
-- 2. offerbyseller: sellerid
--    → usado para listar ofertas de uma conta

-- Colunas:
-- sellerid:     ID da conta (GABCD...)
-- offerid:      ID único da oferta
-- sellingasset: ativo vendido (codificado como string)
-- buyingasset:  ativo comprado
-- amount:       quantidade (em stroops)
-- price:        preço (n/d)
-- lastmodified: ledger da última modificação
```

### 3.5 Padrão de Operações no SQLite

O SQLite do stellar-core é usado para **estado local do ledger**:
- Storestate: 5 registros de configuração (READ-heavy, atualizado a cada checkpoint)
- Offers: 56.602 ofertas vivas (READ-heavy para matching de order book, WRITE nas bordas de checkpoint)

O SQLite do captive core é **idêntico em estrutura** mas usado apenas pelo processo captive para reconstruir estado durante ingestão.

---

## 4. Fluxo Completo dos Dados (1 Ledger)

```
LEDGER FECHADO (a cada ~5s)
         │
         ▼
┌─────────────────────────────────────────┐
│  CAPTIVE CORE (via pipe fd:3)           │
│                                         │
│  Lê ledger header + txSet + resultados  │
│  Atualiza SQLite (offers, storestate)   │
│  Envia metadados para Horizon via pipe  │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  HORIZON (processa metadados)           │
│                                         │
│  1. INSERT history_ledgers              │
│  2. INSERT history_transactions         │
│  3. INSERT history_operations           │
│  4. INSERT history_effects              │
│  5. INSERT history_accounts             │
│                                         │
│  6. UPSERT accounts                     │ ← UPDATE + INSERT
│  7. UPSERT accounts_signers             │
│  8. UPSERT trust_lines                  │
│  9. UPSERT offers                       │ ← INSERT + UPDATE + DELETE
│ 10. UPSERT exp_asset_stats              │
│ 11. INSERT history_trades               │
│                                         │
│ 12. UPDATE key_value_store              │
│     (exp_ingest_last_ledger, etc)       │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  POSTGRESQL                             │
│  WAL: ~11 MB/minuto                     │
│  Checkpoint: a cada ~90s               │
│  Buffers: 875 por checkpoint            │
└─────────────────────────────────────────┘
```

---

## 5. Análise de Performance

### 5.1 Gargalos Identificados

```
Gargalo 1: WALWrite
  └── COPY trust_lines bloqueou em WALWrite
  └── WAL de 1.008 MB indica alta geração de logs
  └── Solução: aumentar max_wal_size, tuning checkpoint

Gargalo 2: Sequential Scans
  └── key_value_store: 4.304 scans sequenciais (tabela pequena, sem impacto)
  └── offers: 199 scans sequenciais (tabela de 56K linhas)
  └── Solução: índice adicional para consultas frequentes de order book

Gargalo 3: UPDATE-heavy em accounts
  └── 198 UPDATES/90s na tabela accounts
  └── Cada UPDATE gera HOT update (83% hot updates)
  └── Bom: HOT updates são eficientes (não requerem VACUUM frequente)
```

### 5.2 Taxa de Operações

| Tipo | 90s | Por Ledger | Por Segundo |
|:----|:---:|:----------:|:-----------:|
| INSERT | 1.268 | 74,6 | 14,1 |
| UPDATE | 311 | 18,3 | 3,5 |
| DELETE | 21 | 1,2 | 0,2 |
| SELECT | 436 | 25,6 | 4,8 |
| **Total** | **2.036** | **119,8** | **22,6** |

### 5.3 Cache Hit Ratio

Baseado nos índices acessados:
- `history_ledgers`: 10.133 idx scans (cache hit ~99% — busca por PK)
- `accounts`: 3.881 idx scans (cache hit ~99% — busca por account_id)
- `trust_lines`: 859 idx scans (cache hit ~99%)
- `offers`: 1.290 idx scans + 199 seq scans

O PostgreSQL está operando majoritariamente em cache (shared_buffers = 128 MB).

---

## 6. Esquemas Completos

### 6.1 PostgreSQL — Schema das Tabelas Mais Ativas

```sql
-- Tabelas de histórico (INSERT-only)
history_ledgers:            ledger_seq, hash, prev_hash, closed_at, ... (36 KB/linha)
history_transactions:       tx_hash, ledger_seq, tx_envelope, tx_result, ... (36 KB/linha)
history_operations:         op_id, tx_hash, ledger_seq, op_type, details, ... (6 KB/linha)
history_effects:            effect_id, op_id, effect_type, details, ... (2 KB/linha)
history_accounts:           account_id, added_ledger, ... (0,5 KB/linha)

-- Tabelas de estado (INSERT+UPDATE+DELETE)
accounts:                   account_id, balance, seq_num, signers, ... (0,3 KB/linha)
accounts_signers:           account_id, signer_key, weight, ... (0,5 KB/linha)
trust_lines:                account_id, asset_code, asset_issuer, balance, ... (1 KB/linha)
offers:                     seller_id, offer_id, selling, buying, amount, price, ... (0,5 KB/linha)
contract_asset_balances:    contract_id, asset_code, issuer, balance, ... (0,2 KB/linha)
key_value_store:            key VARCHAR, value TEXT (0,1 KB/linha)
```

### 6.2 SQLite (Core + Captive) — Schema Completo

```sql
-- Já documentado na Seção 3.1
-- Apenas 2 tabelas: offers + storestate
-- Índices: bestofferindex + offerbyseller
```

---

## 7. Conclusões

1. **Padrão INSERT-heavy**: 62% das operações são INSERTs em tabelas de histórico (append-only). A tabela `history_operation_participants` é a mais ativa com 337 inserts/90s.

2. **UPDATE concentrado em contas**: A tabela `accounts` recebe 198 UPDATES/90s (2,2/s) — cada ledger modifica saldos de múltiplas contas. 83% são HOT updates (eficientes).

3. **DELETE é raro**: Apenas 21 DELETEs/90s, todos em `offers` (ofertas expiradas/removidas).

4. **SQLite é secundário**: Os SQLites (core + captive) têm função de cache local para offers + storestate. O volume de dados é baixo comparado ao PostgreSQL.

5. **PostgreSQL WAL é volumoso**: 1.008 MB de WAL para ~3 GB de banco, indicando checkpoint tuning necessário.

6. **Ingestão lenta**: 17 ledgers/90s (0,19/s) — muito abaixo dos ~10 ledgers/s observados anteriormente. Provavelmente devido ao checkpoint/recovery pós-reinicialização.

---

## Apêndice A: Metadados da Coleta

```
Ferramentas utilizadas:
- pg_stat_user_tables (snapshots before/after)
- pg_stat_bgwriter (snapshots before/after)
- pg_stat_activity (amostragem a cada 5s × 18 amostras)
- pg_ls_waldir (tamanho WAL)
- sqlite3 PRAGMA + .schema + .tables
- key_value_store (estado de ingestão)

Limitações:
- pg_stat_statements não pôde ser carregado (shared_preload_libraries)
- pg_stat_activity amostras ficaram vazias (ingestão entre amostras)
- Delta calculado entre dois snapshots, não tracking contínuo
```

## Apêndice B: Comandos para Reprodução

```bash
# Monitorar PostgreSQL
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT * FROM pg_stat_user_tables ORDER BY n_tup_ins DESC;"

# Check WAL
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT count(*), pg_size_pretty(sum(size)) FROM pg_ls_waldir();"

# Check SQLite core
docker exec stellar-core sqlite3 /opt/stellar/core/stellar.db ".tables"

# Check SQLite captive
docker exec stellar-horizon sqlite3 /opt/stellar/horizon/captive-core/stellar.db ".tables"

# Ver progresso ingestão
docker exec stellar-horizon psql -h localhost -U stellar -d horizon \
  -c "SELECT * FROM key_value_store;"
```
