# Relatório Completo de Sincronização e Estado do Nó Stellar Testnet

**Data do Experimento:** 2026-07-20 (execução em 2026-07-21 02:00 UTC)
**Container:** stellar-testnet (stellar/quickstart:testing)
**Versão Core:** v27.1.0 — Protocolo 27
**Rede:** Test SDF Network ; September 2015
**Estado no Início:** Connected / Catching up (~2,8 dias atrás)
**Estado ao Final:** Synced!

---

## Sumário

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Análise dos Buckets](#2-análise-dos-buckets)
3. [Análise do Banco PostgreSQL (Horizon)](#3-análise-do-banco-postgresql-horizon)
4. [Estrutura dos Checkpoints](#4-estrutura-dos-checkpoints)
5. [Monitoramento de Atividade do Banco (90s)](#5-monitoramento-de-atividade-do-banco-90s)
6. [Análise de Smart Contracts (Soroban)](#6-análise-de-smart-contracts-soroban)
7. [Métricas de Rede e Consenso](#7-métricas-de-rede-e-consenso)
8. [Armazenamento e Recursos do Sistema](#8-armazenamento-e-recursos-do-sistema)
9. [Fluxo Completo dos Dados](#9-fluxo-completo-dos-dados)
10. [Conclusões](#10-conclusões)

---

## 1. Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CONTAINER DOCKER                             │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐             │
│  │  Stellar     │   │  Captive     │   │  Horizon     │             │
│  │  Core Node   │   │  Core        │   │  API         │             │
│  │  (PID 118)   │   │  (PID 310)   │   │  (PID 168)   │             │
│  │              │   │              │   │              │             │
│  │ Porta: 11626 │   │ Porta: 11726 │   │ Porta: 8001  │             │
│  │ P2P: 11625   │   │ P2P: 11725   │   │              │             │
│  │              │   │              │   │              │             │
│  │ SQLite:      │   │ SQLite:      │   │ PostgreSQL:  │             │
│  │ stellar.db   │   │ stellar.db   │   │ horizon (4.9GB)            │
│  │ Buckets:4.3GB│   │ Buckets:4.3GB│   │              │             │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘             │
│         │                  │                  │                     │
│         │ P2P SCP         │ Pipe (fd:3)      │ HTTP API             │
│         ▼                  ▼                  ▼                     │
│  ┌──────────────────────────────────────────────────────┐           │
│  │                  nginx (porta 8000)                   │           │
│  │            Proxy reverso: / → Horizon :8001           │           │
│  └──────────────────────────────────────────────────────┘           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────┐           │
│  │         History Archives (SDF) — Download de dados   │           │
│  │  https://history.stellar.org/prd/core-testnet/       │           │
│  └──────────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

### Processos em Execução

| Processo | PID | CPU% | MEM% | RSS |
|:---------|:----|:-----|:-----|:----|
| Captive Core (Horizon) | 310 | 60,7% | 18,3% | ~2,99 GB |
| Stellar Core | 118 | 47,1% | 16,7% | ~2,74 GB |
| Horizon | 168 | 8,7% | 0,6% | ~102 MB |
| PostgreSQL | 255 | 0,3% | 0,3% | ~55 MB |
| supervisord (PID 1) | 1 | 0,3% | 0,1% | ~28 MB |

---

## 2. Análise dos Buckets

### 2.1 O que são Buckets

Buckets são arquivos XDR que armazenam **snapshots do estado completo** do ledger Stellar. A bucket list é organizada em **níveis de merge** (L0 a L5+), onde níveis mais altos contêm dados mais consolidados e antigos.

```
Bucket Levels:

L0 (fresco) ─── Pequenos (<1 MB) ─── 22 arquivos ─── Dados novos, não mergeados
L1 ──────────── 1-10 MB ─────────────  6 arquivos ─── Merge parcial
L2 ──────────── 10-100 MB ───────────  7 arquivos ─── Merge intermediário
L3 ──────────── 100-202 MB ──────────  4 arquivos ─── Consolidado
L4 ──────────── 200-452 MB ──────────  4 arquivos ─── Profundo
L5 (snap) ───── 600-785 MB ──────────  3 arquivos ─── Snapshot completo
```

### 2.2 Inventário de Buckets — Core Node

Distribuição dos 49 arquivos `.xdr` em `/opt/stellar/core/buckets/`:

```
Tamanho    │ Quantidade │ Nível   │ Período de Criação
───────────┼────────────┼─────────┼─────────────────────
785 MB     │     1      │  L5     │ 16/07 01:04
610 MB     │     1      │  L5     │ 16/07 01:02
600 MB     │     1      │  L5     │ 16/07 01:04
452 MB     │     1      │  L4     │ 16/07 01:02
355 MB     │     1      │  L4     │ 16/07 01:02
310 MB     │     1      │  L4     │ 16/07 01:01
266 MB     │     1      │  L4     │ 16/07 00:58
202 MB     │     1      │  L3     │ 16/07 01:00
192 MB     │     1      │  L3     │ 16/07 01:04
153 MB     │     1      │  L3     │ 16/07 01:00
121 MB     │     1      │  L3     │ 16/07 00:58
 98 MB     │     1      │  L2     │ 16/07 01:04
 69 MB     │     1      │  L2     │ 16/07 00:59
 55 MB     │     1      │  L2     │ 18/07 00:34
 30 MB     │     1      │  L2     │ 18/07 00:40
 25 MB     │     1      │  L2     │ 16/07 00:58
 20 MB     │     1      │  L2     │ 18/07 00:42
 14 MB     │     1      │  L2     │ 18/07 00:34
 <10 MB    │    28      │  L0-L1  │ 18-19/07
 ────────  │ ────────   │         │
 4,27 GB   │    49      │ Total   │
```

### 2.3 Distribuição por Conteúdo (Bucket List)

Dados obtidos das métricas do stellar-core, representando o estado completo da rede:

```
Composição do Estado da Testnet:

PERSISTENT_CONTRACT_DATA   4.193.309 entradas (716 MB)  ████████████████████████████████████████ 40,2%
ACCOUNT                    2.956.700 entradas (374 MB)  ████████████████████████████████████████ 21,0%
CONTRACT_CODE                 22.544 entradas (304 MB)  ████████████████████████████████████████ 17,1%
TTL                        4.356.785 entradas (208 MB)  ████████████████████████████████████████ 11,7%
DATA (account)               332.654 entradas ( 49 MB)  ████████████████████████████████████████  2,8%
TRUSTLINE                    325.706 entradas ( 45 MB)  ████████████████████████████████████████  2,5%
TEMPORARY_CONTRACT_DATA      143.452 entradas ( 22 MB)  ████████████████████████████████████████  1,2%
OFFER                         53.382 entradas (  9 MB)  ████████████████████████████████████████  0,5%
CLAIMABLE_BALANCE             8.918 entradas (  2 MB)   ████████████████████████████████████████  0,1%
LIQUIDITY_POOL                2.592 entradas (422 KB)   ████████████████████████████████████████ <0,1%
CONFIG_SETTING                   40 entradas (  5 KB)   ████████████████████████████████████████ <0,1%

Soroban (PERSISTENT_CONTRACT + CONTRACT_CODE + TTL + TEMPORARY): ~70,1% do estado
Não Soroban (ACCOUNT + DATA + TRUSTLINE + OFFER + etc.):          ~29,9% do estado
```

### 2.4 Buckets do Captive Core vs Core Node

O Captive Core do Horizon mantém buckets **independentes** em `/opt/stellar/horizon/captive-core/captive-core/buckets/`.

```
Comparação:

                    Core Node    Captive Core     Duplicação
Arquivos .xdr:      49           43               25 hashes idênticos
Tamanho total:      4,272 GB     4,273 GB          ~4,1 GB duplicados
Arquivos .index:    30 (86 MB)   0                —
Bucket sentinela:   1 (20 bytes) 1 (20 bytes)     —

Custo total de armazenamento de buckets: ~8,5 GB (2x por causa da arquitetura de isolamento)
```

### 2.5 Top 5 Maiores Buckets

```
Arquivo                                        Tamanho    Nível
bucket-ff26b4f5...7efd.xdr                    785 MB     L5 (snap mais profundo)
bucket-eb7625ce...4b72.xdr                    610 MB     L5
bucket-d8522ede...2d730.xdr                   600 MB     L5
bucket-8a27deda...b125.xdr                    452 MB     L4
bucket-b2a2c09a...d09b.xdr                    355 MB     L4
```

---

## 3. Análise do Banco PostgreSQL (Horizon)

### 3.1 Visão Geral

| Banco | Tamanho | Conexão |
|:------|:--------|:--------|
| **horizon** | **4.924 MB** (~4,8 GB) | localhost:5432 |
| postgres | 8.441 kB | template |
| template0 | 8.441 kB | template |
| template1 | 8.441 kB | template |

### 3.2 Todas as Tabelas por Tamanho

```
Tabela                                   Tamanho Total   Índices   Linhas (est.)
───────────────────────────────────────────────────────────────────────────────
accounts_signers                         1.433 MB        1.002 MB     2.977.063
history_transactions                     1.316 MB           73 MB      417.503
accounts                                   877 MB          375 MB    2.899.477
history_operations                         403 MB           25 MB      612.480
trust_lines                                282 MB          172 MB      325.706
accounts_data                              221 MB          126 MB      332.688
history_operation_participants              87 MB           49 MB      858.132
history_effects                             72 MB           22 MB      242.846
history_transaction_participants            70 MB           38 MB      684.934
history_ledgers                             36 MB          1,7 MB       36.421
offers                                      35 MB           22 MB       47.440
exp_asset_stats                             35 MB           11 MB       53.913
contract_asset_balances                     13 MB            6 MB       56.663
claimable_balances                          12 MB            7 MB        8.747
claimable_balance_claimants                 12 MB            9 MB       18.455
history_accounts                          6.440 kB             —        25.666
liquidity_pools                           1.792 kB             —         2.577
history_trades                            1.216 kB             —         1.620
history_trades_60000                        520 kB             —         1.446
asset_contracts                             512 kB             —           695
contract_asset_stats                        320 kB             —         1.191
demais (13 tabelas)                        ~600 kB             —       <1.000 cada
───────────────────────────────────────────────────────────────────────────────
Total (33 tabelas):                       4.924 MB              —     ~9,3M linhas
```

### 3.3 Contagem Exata de Linhas

```
Tabela                     Linhas
────────────────────────────────
accounts                   2.918.298
accounts_signers           2.997.226
trust_lines                  327.289
offers                        53.382
history_ledgers               39.328
history_transactions         432.432
history_operations           642.487
history_effects              249.575
history_trades                 1.832
liquidity_pools                2.592
claimable_balances             8.918
contract_asset_balances       57.698
contract_asset_stats           1.191
asset_contracts                  695
────────────────────────────────
```

### 3.4 Estado de Ingestão (`key_value_store`)

| Chave | Valor |
|:------|:------|
| exp_state_invalid | false |
| exp_ingest_version | 20 |
| exp_ingest_last_ledger | 3.672.313 |
| offer_compaction_sequence | 3.672.213 |
| liquidity_pool_compaction_sequence | 3.672.213 |

### 3.5 Últimos Ledgers Ingeridos

| Ledger Seq | Hash | Fechado Em |
|:-----------|:-----|:-----------|
| 3.668.639 | e3e06cf2... | 2026-07-18 07:39:05 |
| 3.668.638 | 767599e0... | 2026-07-18 07:39:00 |
| 3.668.637 | 5630ae71... | 2026-07-18 07:38:55 |
| 3.668.636 | 6c9c2015... | 2026-07-18 07:38:50 |
| 3.668.635 | dc0d91e1... | 2026-07-18 07:38:45 |

---

## 4. Estrutura dos Checkpoints

### 4.1 O que é um Checkpoint

Um checkpoint Stellar agrupa **64 ledgers consecutivos** (~5 minutos e 20 segundos de atividade da rede). A cada checkpoint, o nó publica arquivos no history archive contendo o histórico completo daquele intervalo.

```
Checkpoint N ─── 64 ledgers ─── Cobre ~5 min 20s da rede
  │
  ├── Chunk 1: ledgers 0-15
  ├── Chunk 2: ledgers 16-31
  ├── Chunk 3: ledgers 32-47
  └── Chunk 4: ledgers 48-63
```

### 4.2 Arquivos de um Checkpoint

Para cada checkpoint, os seguintes arquivos são armazenados no history archive:

```
URL: https://history.stellar.org/prd/core-testnet/core_testnet_001/
                        │
        ┌───────────────┴───────────────┐
        │                               │
  history-XXXX.json             XX/YY/ZZ/
        │                               │
  stellar-history.json     ┌─────┬──────┼──────┬─────┐
                          │     │      │      │     │
                     ledger/ txs/  results/ scp/ buckets/

Estrutura de diretórios no archive:
  XX/YY/ZZ/ledger/ledger-XXXXYYff.xdr    (4 chunks: 3f, 7f, bf, ff)
  XX/YY/ZZ/transactions/transactions-XXXXYYff.xdr
  XX/YY/ZZ/results/results-XXXXYYff.xdr
  XX/YY/ZZ/scp/scp-XXXXYYff.xdr
```

Onde `XXXXYY` = número do checkpoint em hex, e `XX/YY/ZZ` = primeiros 6 dígitos hex em pares.

### 4.3 Conteúdo de Cada Arquivo

```
ledger-*.xdr
  └── Sequência de LedgerHeaderHistoryEntry
      ├── Hash do ledger
      ├── LedgerHeader (versão, ledgerSeq, previousLedgerHash, scpValue,
      │                 txSetResultHash, bucketListHash, totalCoins,
      │                 feePool, baseFee, baseReserve, maxTxSetSize, ...)
      └── Extensão

transactions-*.xdr
  └── Sequência de TransactionHistoryEntry
      ├── ledgerSeq
      ├── TransactionEnvelopeList (todas as transações do chunk)
      │   ├── Envelope V1 (regular)
      │   │   ├── tx: sourceAccount, fee, seq, timeBounds, operations[], memo
      │   │   ├── signatures[]
      │   │   └── SorobanData (resources: instructions, readBytes, writeBytes)
      │   └── Envelope V0 (legacy)
      └── Resultados (extensão opcional)

results-*.xdr
  └── Sequência de TransactionHistoryResultEntry
      ├── ledgerSeq
      └── TransactionResultPairList
          ├── TransactionResult (success/failure)
          │   ├── feeCharged
          │   ├── result code
          │   ├── operations[]
          │   │   ├── tr (código de resultado específico)
          │   │   └── SorobanMeta (events[], returnValue, diagnosticEvents)
          │   └── ext (Soroban: events[], returnValue, diagnosticEvents)
          └── (hash da tx correspondente)

scp-*.xdr
  └── Sequência de SCPHistoryEntry
      ├── SCP envelopes (nominate, prepare, confirm, externalize)
      ├── Quorum set
      └── Votos e confirmações dos validadores
```

### 4.4 Frequência na Testnet

```
Ledgers por checkpoint:  64
Tempo por ledger:        ~5 segundos
Tempo por checkpoint:    ~5 min 20s
Ledger atual:            3.672.375
Checkpoint atual:        57.381 (3.672.375 ÷ 64)
```

### 4.5 Buckets Referenciados

O arquivo `stellar-history.json` referência os hashes dos buckets que compõem o snapshot de estado do ledger no checkpoint:

```
stellar-history.json
  ├── version: 2
  ├── server: "stellar-core 27.1.0"
  ├── currentLedger: <número>
  ├── networkPassphrase: "Test SDF Network ; September 2015"
  └── currentBuckets[]
      ├── level 0: curr=<hash>, snap=<hash>, next={state}
      ├── level 1: curr=<hash>, snap=<hash>, next={state}
      ├── ...
      ├── level 5: curr=<hash>, snap=<hash>, next={state}
      └── hotArchiveBuckets[]
```

---

## 5. Monitoramento de Atividade do Banco (90s)

### 5.1 Progresso do Ledger Durante a Janela

Durante os 90 segundos de monitoramento, o nó processou **910 novos ledgers** (~10 ledgers/segundo):

```
Métrica                Antes (T1)    Depois (T2)    Δ
Core latest            3.671.465     3.672.375     +910
Ingest latest          3.671.464     3.672.374     +910
History latest         3.671.464     3.672.374     +910
exp_ingest_last_ledger 3.671.455     3.672.313     +858
offer_compaction       3.671.355     3.672.213     +858
```

### 5.2 Atividade por Tabela (Δ em 90 segundos)

```
Tabela                                     Δ Inserts   Δ Updates   Δ Deletes   Δ Live
─────────────────────────────────────────────────────────────────────────────────────
history_operation_participants              +17.445          0           0     +17.445
history_transaction_participants            +13.491          0           0     +13.491
history_operations                          +12.109          0           0     +12.109
history_transactions                        +7.781           0           0     +7.781
history_effects                             +5.861           0           0     +5.861
history_ledgers                             +800             0           0     +800
offers                                      +578           +596        +550        +28
history_accounts                            +449             0           0        +449
trust_lines                                 +458         +2.106         +33        +425
accounts                                    +416         +8.272         +96        +320
accounts_signers                            +416             0         +97        +319
history_trades_60000                        +312             0        +263        +49
claimable_balance_claimants                 +243             0         +28        +215
claimable_balances                          +108             0         +14         +94
contract_asset_balances                      +34          +171         +80          +5
exp_asset_stats                              +32          +360           0         +32
key_value_store                                0        +2.400           0           0
contract_asset_stats                           0          +215           0           0
─────────────────────────────────────────────────────────────────────────────────────
Total de inserts:                         ~60.000
Total de updates:                         ~14.000
Total operações no banco:                 ~74.000 em 90s (~822 ops/s)
```

### 5.3 Visualização da Taxa de Operações

```
Taxa de operações no banco (por segundo em 90s):

                  ┌──────┐
history_op_partic ┤ ████████████████████████████████████████████████████  194/s
history_tx_partic ┤ ██████████████████████████████████████████████████    150/s
history_operations┤ ███████████████████████████████████████████████      135/s
history_transactns┤ ██████████████████████████████████████                86/s
history_effects   ┤ █████████████████████████████                        65/s
accounts (upd)    ┤ ████████████████████████████████████████████████████   92/s
accounts (ins)    ┤ █████▌                                                  5/s
trust_lines (upd) ┤ ██████████                                             23/s
key_value_store   ┤ ███████████                                            27/s
contract_asset_st ┤ ██▌                                                     2/s
──────────────────┴──────────────────────────────────────────────────────────
                   Total: ~822 operações/segundo no banco
```

### 5.4 Padrão de Ingestão

```
Fluxo de ingestão do Horizon a cada ledger:

1. Novo ledger chega do Captive Core via pipe
2. INSERT history_ledgers          (+1)
3. INSERT history_transactions     (+~8,5 txs/ledger)
4. INSERT history_operations       (+~13,3 ops/ledger)
5. INSERT history_effects          (+~6,4 effects/ledger)
6. INSERT/UPDATE accounts          (+0,45 + ~9,1 updates/ledger)
7. INSERT/UPDATE trust_lines       (+0,5 + ~2,3 updates/ledger)
8. INSERT/UPDATE offers            (+0,6 + ~0,6 updates/ledger)
9. INSERT participants             (+~19 + ~15/ledger)
10. UPDATE key_value_store         (+~2,6/ledger)
11. UPDATE contract_asset_stats    (+~0,2/ledger)
12. (a cada 100 ledgers) UPDATE exp_ingest_last_ledger
```

---

## 6. Análise de Smart Contracts (Soroban)

### 6.1 Onde os Dados Soroban Residem

O Soroban armazena dados em **três camadas** distintas:

```
              ┌─────────────────────────────────────────────────────────────────┐
              │                   BUCKETS (Stellar Core)                        │
              │                  Armazenamento Primário do Ledger               │
              │                                                                 │
              │  ┌──────────────────────────────────────────────────────────┐   │
              │  │  PERSISTENT_CONTRACT_DATA   4.193.309 entries  716 MB   │   │
              │  │  CONTRACT_CODE                 22.544 entries  304 MB   │   │
              │  │  TTL                         4.356.785 entries  208 MB  │   │
              │  │  TEMPORARY_CONTRACT_DATA       143.452 entries   22 MB  │   │
              │  │                                         Total: 1,25 GB  │   │
              │  └──────────────────────────────────────────────────────────┘   │
              └─────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │               SQLITE (Stellar Core)                            │
              │              Metadados Operacionais Transitórios               │
              │                                                                 │
              │  stellar.db (21 MB) — sem dados específicos de contrato         │
              │  Apenas tabelas: offers, storestate                             │
              └─────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │             POSTGRESQL (Horizon)                               │
              │            Dados Históricos Indexados para Consulta            │
              │                                                                 │
              │  contract_asset_balances   57.698 linhas   13 MB                │
              │  contract_asset_stats       1.191 linhas  320 KB                │
              │  asset_contracts              695 linhas  512 KB                │
              │  history_operations (tipo 24, 25, 26)  303.527 linhas          │
              └─────────────────────────────────────────────────────────────────┘
```

### 6.2 Tipos de Operação Soroban no Histórico

```
Distribuição de operações Soroban no history_operations:

Tipo 24 — invokeHostFunction     303.527   ████████████████████████████████████████████████ 98,5%
Tipo 25 — extendFootprintTTL       4.565   █▌                                                1,5%
Tipo 26 — restoreFootprint            13   ▎                                                 <0,1%
                                   ───────
Total Soroban:                   308.105

Comparação com operações não-Soroban:
  Total operações no histórico:  630.422
  Soroban:                       308.105  (48,9%)
  Não-Soroban:                   322.317  (51,1%)
```

### 6.3 Cache de Módulos Soroban (em memória)

O stellar-core mantém um cache em RAM com os módulos WASM compilados:

```
soroban.module-cache.num-entries:    4.625 contratos em cache
soroban.module-cache.rebuild-bytes:  124.919.414 bytes (~119 MB)
soroban.module-cache.rebuild-time:   6.493 ms (uma reconstrução)
soroban.module-cache.compil-time:    53 ms cumulativo
```

### 6.4 Contratos vs Contas

```
Comparação contratos Soroban vs contas tradicionais:

                            Soroban          Não-Soroban
Contagens:
  Entradas bucket list:     8.716.090 (70%)   3.660.175 (30%)
  Armazenamento em bucket:  1.250 MB (70%)      533 MB (30%)
  Operações no histórico:     308.105 (49%)     322.317 (51%)

Taxa de sucesso:
  Aplicações com sucesso:        18.692          23.634
  Falhas:                           123               0
  Taxa de sucesso:              99,35%           100%

Limites:
  Tamanho máximo tx:        132.096 bytes      (limitado pelo ledger)
  Instruções CPU máx:       400.000.000        (não se aplica)
  Memória máxima:           41.943.040 bytes   (não se aplica)
  Entradas leitura máx:     200                (não se aplica)
  Entradas escrita máx:     200                (não se aplica)
```

### 6.5 Fluxo de Processamento de uma Transação Soroban

```
Transação Soroban entra no mempool
         │
         ▼
┌─────────────────────┐
│  1. Herder recebe   │────→ Verifica fee, seq, signature
│     transação       │      Verifica footprint (ledger keys acessadas)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  2. Líder SCP       │────→ Inclui no txSet (max 2.000 Soroban txs)
│     propõe conjunto │      Limite de 266.240 bytes Soroban/ledger
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  3. Consenso SCP    │────→ Nominate → Prepare → Confirm → Externalize
│     (todos nós)     │      Envelopes SCP assinados por validadores
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  4. Apply ledger    │────→ 4 estágios (soroban.stages=1 max-clusters=1)
│                     │
│  4a. Carrega WASM   │────→ Module cache hit? Se não: compila WASM
│                      │      (4.625 módulos em cache, 119 MB)
│  4b. Verifica        │────→ Read footprint: tx-max-read-entry=200
│      footprint       │      Read-ledger-byte: 200.000 bytes
│  4c. Executa         │────→ VM WASM executa host function
│      contrato        │      Contagem de instruções: max 400M
│                      │      Memória: max 40 MB por transação
│  4d. Escreve         │────→ Write footprint: tx-max-write-entry=200
│      resultados      │      Write-ledger-byte: 132.096 bytes
│  4e. Gera eventos    │────→ tx-max-emit-event-byte: 16.384
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  5. Verificação     │────→ Invariantes: 0 falhas
│     de invariantes  │      Soroban: 18.698 sucessos, 123 falhas
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  6. Commit nos      │────→ Bucket list: merge de L0 em diante
│     buckets         │      TTL gerenciado via extendFootprintTTL
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  7. Horizon ingere  │────→ Captive core → pipe → PostgreSQL
│     metadados       │      INSERT história + UPDATE estado atual
└─────────────────────┘
```

---

## 7. Métricas de Rede e Consenso

### 7.1 Estado da Conexão P2P

```
Status da rede no momento da coleta:

Peers autenticados:           3              (sdf_testnet_1, 2, 3)
Peers pendentes:              55
Tentativas de saída:          177            (98% de churn: 174 drops)
Timeouts idle:                160
Timeouts straggler:           0
```

### 7.2 Tráfego de Rede

```
Tráfego P2P desde o início do nó:

Métrica                    Recebido    Enviado
Bytes                      496.464     66.372
Mensagens                    1.210        251
Mensagens SCP                  881        127
  scp-nominate                 260
  scp-prepare                  318
  scp-confirm                   83
  scp-externalize              220

Flood:
  Mensagens únicas recebidas:         128.740
  Mensagens duplicadas recebidas:     223.320
  Mensagens broadcast:                       127
```

### 7.3 Consenso SCP

```
Envelopes SCP recebidos:             1.014
Envelopes SCP assinados:                28
Envelopes SCP com validação OK:        481
Envelopes SCP inválidos:                  0
Envelopes SCP fetch:                   133 (média 86,4ms)
Timeout nominate:                         7
Timeout prepare:                           7
Ballot blocked on txset:                   7
Sync lost:                                  1
```

### 7.4 Verificações Criptográficas

```
Verificações SHA256 totais:    1.685
  Hit (cache):                 1.311
  Miss:                          374
Verificações de transação:         0 (nó em catchup)
```

---

## 8. Armazenamento e Recursos do Sistema

### 8.1 Armazenamento Total

```
/opt/stellar/              15,0 GB
│
├── core/                   4,6 GB   ── Stellar Core Node
│   ├── buckets/            4,4 GB   ── 49 arquivos .xdr + 30 .index
│   ├── stellar.db          21  MB   ── SQLite (ledgers + storestate)
│   ├── stellar.db-wal      44  MB   ── Write-Ahead Log
│   └── stellar.db-shm      64  KB   ── Shared Memory
│
├── horizon/                4,7 GB   ── Captive Core (Horizon)
│   ├── captive-core/       4,6 GB   ── buckets replicados
│   │   ├── buckets/        4,3 GB   ── 43 arquivos .xdr
│   │   └── stellar.db      21  MB   ── SQLite próprio
│   └── ...
│
├── postgresql/             5,3 GB   ── PostgreSQL (Horizon data)
│   └── base/horizon        4,9 GB   ── 33 tabelas, ~9,3M linhas
│
├── lab/                   171  MB   ── Stellar Lab
└── outros (nginx,          200 KB
     supervisor, friendbot, 
     stellar-rpc, galexie)
```

### 8.2 Recursos de Hardware

```
RAM total:       15,0 GB
RAM em uso:       6,6 GB  (44%)
RAM livre:        2,2 GB
Buffer/Cache:     7,1 GB

Swap total:       4,0 GB
Swap em uso:      0      (sem swap)

CPU:              Captive Core 60,7% + Core Node 47,1% + Horizon 8,7%
                  ≈ 117% de CPU utilizada (containers não têm limite)

Disco (Docker):   1.007 GB total, 34 GB usado (4%)
```

---

## 9. Fluxo Completo dos Dados

### 9.1 Pipeline do Ledger ao Banco

```
History Archives (SDF)
  https://history.stellar.org/prd/core-testnet/
         │
         ├─────────────────────┬──────────────────────┐
         ▼                     ▼                      ▼
┌────────────────┐   ┌────────────────┐   ┌──────────────────────┐
│ Core Node      │   │ Captive Core   │   │ Horizon              │
│                │   │                │   │                      │
│ Baixa buckets  │   │ Baixa buckets  │   │ Lê metadados via     │
│ Baixa checkpts │   │ Baixa checkpts │   │ pipe fd:3 do         │
│ SCP Consensus  │   │ (sem SCP)      │   │ captive core         │
│                │   │                │   │                      │
│ SQLite local   │   │ SQLite local   │   │ PostgreSQL           │
│ stellar.db     │   │ stellar.db     │   │ 33 tabelas           │
│ buckets/       │   │ buckets/       │   │ 4,9 GB de dados     │
└───────┬────────┘   └───────┬────────┘   └──────────────────────┘
        │                    │                        ▲
        │ P2P (SCP)         │ Pipe (metadata output   │
        │                    │   stream fd:3)          │
        │                    ▼                         │
        │          ┌─────────────────────┐            │
        │          │ Para cada ledger:   │────────────┘
        │          │  - LedgerHeader     │
        │          │  - TxSet            │
        │          │  - TxProcessing     │
        │          │  - Operations       │
        │          │  - Effects          │
        │          │  - AccountChanges   │
        │          │  - Trades           │
        │          │  - SorobanMeta      │
        │          └─────────────────────┘
        │
        ▼
┌───────────────────┐
│ P2P Network       │
│ 3 validadores SDF │
│ core-testnet1..3  │
│ porta 11625       │
└───────────────────┘
```

### 9.2 Pipeline de Dados do Soroban

```
Transação Soroban (ex: invokeHostFunction)
         │
         ▼
┌───────────────────────────────────────────────────┐
│               1. MEMPOOL (Herder)                  │
│  pending-soroban-txs: 0 (sem backlog atualmente)  │
│  maxSorobanTxSetSize: 2.000 transações/ledger     │
└─────────────────────┬─────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│             2. EXECUÇÃO (VM WASM)                  │
│                                                     │
│  ┌──────────┐   ┌──────────┐   ┌───────────────┐   │
│  │ Module   │   │ Footprint│   │ Host Function │   │
│  │ Cache    │──▶│ Check    │──▶│ Execution     │   │
│  │ 4.625    │   │ 200 rd   │   │ WASM sandbox  │   │
│  │ contratos│   │ 200 wr   │   │ max 400M inst │   │
│  └──────────┘   └──────────┘   └───────┬───────┘   │
│                                        │           │
│                              ┌─────────▼───────┐   │
│                              │    Resultado:    │   │
│                              │  - return value  │   │
│                              │  - events        │   │
│                              │  - diagnostic    │   │
│                              │  - estado alter. │   │
│                              └─────────────────┘   │
└───────────────────────────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│          3. COMMIT NOS BUCKETS                     │
│                                                     │
│  BucketList:                                        │
│  L0 ── merge ──▶ L1 ── merge ──▶ ... ──▶ L5       │
│                                                     │
│  Entradas escritas:                                 │
│  - PERSISTENT_CONTRACT_DATA  (716 MB)              │
│  - CONTRACT_CODE              (304 MB)              │
│  - TTL                        (208 MB)              │
│  - TEMPORARY_CONTRACT_DATA     (22 MB)              │
└───────────────────────────────────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────────────┐
│        4. INGESTÃO NO HORIZON (PostgreSQL)         │
│                                                     │
│  Tabelas atualizadas:                               │
│  - history_operations (tipo 24, 25, 26)            │
│  - contract_asset_balances (57.698 linhas)          │
│  - contract_asset_stats (1.191 linhas)              │
│  - asset_contracts (695 linhas)                     │
└───────────────────────────────────────────────────┘
```

---

## 10. Conclusões

1. **Soroban domina o estado da Testnet.** 70% das entradas do ledger (~8,7M de ~12,4M) e 70% do armazenamento em buckets são de contratos inteligentes. A Testnet tem atividade intensa de contratos, com 22.544 códigos WASM únicos em cache.

2. **A duplicação de buckets (8,5 GB) entre Core Node e Captive Core** é intencional para isolar o consenso (Core Node) da ingestão de dados (Horizon), mas representa 57% de todo o armazenamento do nó.

3. **PostgreSQL consome 4,9 GB** com 33 tabelas e ~9,3M de linhas. A tabela mais pesada é `accounts_signers` (1,4 GB), refletindo a natureza multi-sig do Stellar.

4. **Taxa de 822 operações/segundo no banco** durante catch-up, com pico de 194 inserts/s em `history_operation_participants`. O nó processa ~10 ledgers/segundo em regime de catch-up.

5. **Checkpoints armazenam 4 tipos de arquivos XDR** (ledger headers, transactions, results, SCP) organizados em chunks de 16 ledgers. Cada checkpoint cobre 64 ledgers (~5 min 20s).

6. **O Cache de Módulos Soroban (4.625 contratos, 119 MB)** mantém WASM compilado em RAM, evitando recompilação em chamadas repetidas de contrato. Foi reconstruído uma vez em 6,5 segundos.

7. **48% de todas as operações históricas são Soroban** (303.527 invokeHostFunction + 4.578 TTL/restore), indicando que a atividade de contratos inteligentes já é comparável à atividade tradicional de pagamentos na Testnet.

---

## Apêndice A: Estrutura XDR de um Bucket

```
Bucket XDR header (primeiros 16 bytes):

80 00 00 10    ── Discriminante XDR (LedgerEntry)
ff ff ff ff    ── Número de entradas (-1 = sinalizador de continuação)
00 00 00 1b    ── Protocolo 27 (0x1b = 27)
00 00 00 01    ── Flags (inicialização)
```

## Apêndice B: Comandos Utilizados para Coleta

```bash
# Info do nó
curl -s http://localhost:11626/info

# Métricas completas
curl -s http://localhost:11626/metrics

# Listar buckets
ls -lhS /opt/stellar/core/buckets/*.xdr

# Status do supervisor
supervisorctl status

# Query PostgreSQL
psql -h localhost -U stellar -d horizon -c "SELECT ..."

# Query SQLite
sqlite3 /opt/stellar/core/stellar.db "SELECT ..."

# Status do Horizon
curl -s http://localhost:8001/
```

## Apêndice C: Perguntas Frequentes (FAQ)

### Por que a porcentagem oscila durante o catch-up?
Novos ledgers são produzidos pela rede a cada ~5s, aumentando o denominador do cálculo de progresso enquanto o nó processa checkpoints antigos. A porcentagem calculada é `(restantes / total_atual)`, onde `total_atual` cresce continuamente (alvo móvel).

### Quantos checkpoints precisam ser baixados?
Depende do bucket snapshot mais recente disponível. Com `CATCHUP_RECENT=100`, o nó baixa o snapshot disponível mais próximo e replaya todos os checkpoints intermediários. No caso analisado, foram 247 checkpoints (~15.808 ledgers).

### Buckets e checkpoints são a mesma coisa?
Não. Buckets são snapshots completos do estado (arquivos grandes, ~785 MB o maior). Checkpoints são logs de transações de 64 ledgers (arquivos pequenos, aplicação lenta porque cada transação precisa ser reprocessada no SQLite).

### Onde ficam os dados de contratos inteligentes?
Os dados crus ficam nos buckets do Core/Captive Core (PERSISTENT_CONTRACT_DATA, CONTRACT_CODE, TTL). O Horizon extrai metadados selecionados para PostgreSQL em tabelas como `contract_asset_balances`, `contract_asset_stats`, e `asset_contracts`.

### Por que existem dois stellar-cores?
O Core Node (porta 11626) participa do consenso SCP/P2P. O Captive Core (porta 11726) é gerenciado pelo Horizon apenas para fornecer metadados de ledger via pipe, sem participar do consenso. Isso isola a ingestão de dados do processo de consenso.
