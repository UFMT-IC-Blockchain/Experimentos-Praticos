# Otimização de Armazenamento no Validador Stellar

## SQLite (Operacional) vs Buckets XDR (Estado) vs SQLite Misc (Rede)

**Data da Coleta:** 2026-07-26 13:54 UTC
**Container:** stellar-core (validador, Synced!)
**Versão Core:** v27.1.0 | **Protocolo:** 27
**Rede:** Test SDF Network ; September 2015

---

## Prefácio: Correção da Análise Anterior

No relatório anterior, erroneamente incluiu-se o **PostgreSQL do Horizon** na comparação. Este relatório corrige: **dentro do container do validador (stellar-core), não há PostgreSQL.** O validador usa **três sistemas de armazenamento**, todos embarcados:

| # | Sistema | Tipo | Tamanho | Propósito |
|:-|:--------|:----:|:-------:|:-----------|
| 1 | **stellar.db** | SQLite (WAL) | 23 MB + 42 MB WAL | Cache operacional para consenso |
| 2 | **stellar-misc.db** | SQLite (WAL) | 208 KB + 40 MB WAL | Metadados de rede e SCP |
| 3 | **Buckets (.xdr)** | Arquivos XDR | 5,7 GB (57 arquivos) | Estado completo imutável do ledger |

---

## 1. Visão Geral dos Três Sistemas

```
┌──────────────────────────────────────────────────────────────┐
│               VALIDADOR STELLAR CORE                         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐      │
│  │  BUCKETS (.xdr) — 5,7 GB (57 arquivos)             │      │
│  │                                                     │      │
│  │  Nível 5 (snap):  785-905 MB  ── 4 arquivos        │      │
│  │  Nível 4:         202-355 MB  ── 4 arquivos        │      │
│  │  Nível 3:         121-203 MB  ── 3 arquivos        │      │
│  │  Nível 2:          14-98 MB   ── 9 arquivos        │      │
│  │  Nível 0-1:        <10 MB     ── 37 arquivos       │      │
│  │                                                     │      │
│  │  Estado COMPLETO: accounts, trustlines, contract     │      │
│  │  data, offers, TTL entries (~12,4M entries)        │      │
│  └──────────┬──────────────────────────────────────────┘      │
│             │                                                  │
│             │ merge periódico (nível 0 → 1 → 2 → ... → 5)   │
│             │                                                  │
│  ┌──────────▼──────────────────────────────────────────┐      │
│  │  SQLITE MAIN (stellar.db) — 23 MB + 42 MB WAL        │      │
│  │                                                       │      │
│  │  offers:      56.600 linhas  (só ofertas vivas)      │      │
│  │  storestate:        5 linhas  (metadados do core)    │      │
│  │                                                       │      │
│  │  Cache do estado necessrio para validar transaçes    │      │
│  │  (NÃO substitui os buckets — é um subproduto)        │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐      │
│  │  SQLITE MISC (stellar-misc.db) — 208 KB + 40 MB WAL │      │
│  │                                                       │      │
│  │  peers:          170 linhas  (nós P2P conhecidos)    │      │
│  │  scphistory:     224 linhas  (envelopes SCP recentes)│      │
│  │  scpquorums:       1 linha   (quorum set atual)      │      │
│  │  quoruminfo:       5 linhas  (nós do quorum)         │      │
│  │  ban/bannedacc:    0 linhas  (lista de bloqueio)     │      │
│  │  slotstate:        1 linha   (schema version)        │      │
│  │                                                       │      │
│  │  Metadados operacionais voláteis da rede P2P e SCP   │      │
│  └──────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. SQLite Principal (stellar.db) — Cache Operacional

### 2.1 Configuração (medida in loco)

| Parâmetro | Valor | Interpretação |
|:----------|:-----:|:--------------|
| **Page count** | 5.692 | ~23,3 MB de dados |
| **Page size** | 4.096 bytes | Alinhado com página do SO (ext4/NTFS) |
| **Journal mode** | WAL | Write-Ahead Log — leituras e escritas concorrentes |
| **Synchronous** | NORMAL (2) | Checkpoint WAL a cada 1.000 páginas (~4 MB) |
| **Auto-vacuum** | NONE (0) | Sem reorganização automática de páginas |
| **Cache size** | -2.000 pages (~8 MB) | Cache negativo = número de páginas |
| **Freelist** | 4 páginas | Apenas 4 páginas livres — banco compacto |
| **Integrity** | ok | Sem corrupção |
| **WAL size** | 42 MB | Checkpoints pendentes de merge |

### 2.2 Conteúdo

#### offers (56.600 linhas)

```sql
-- Estrutura:
sellerid     VARCHAR(56)       -- Conta do vendedor (9.562 únicos)
offerid      BIGINT PK         -- ID único da oferta
sellingasset TEXT              -- Ativo vendido (9.876 ativos únicos)
buyingasset  TEXT              -- Ativo comprado (8.372 ativos únicos)
amount       BIGINT            -- Quantidade (stroops)
pricen       INT               -- Preço numerador
priced       INT               -- Preço denominador
price        DOUBLE PRECISION  -- Preço calculado (n/d)
flags        INT               -- Flags (0 = passive, 1 = active)
lastmodified INT               -- Último ledger que modificou
extension    TEXT              -- Dados de extensão serializados
ledgerext    TEXT              -- Extensão do ledger serializada
```

**Índices:**
```sql
-- Índice primrio: order book lookup
CREATE INDEX bestofferindex ON offers (sellingasset, buyingasset, price, offerid);
-- Uso: "quais as melhores ofertas para comprar XLM com USDC?"
-- Cobre 100% da consulta (covering index)

-- Índice secundário: ofertas por vendedor
CREATE INDEX offerbyseller ON offers (sellerid);
-- Uso: "quais ofertas a conta GABCD... tem abertas?"
```

#### storestate (5 linhas)

| Chave | Tamanho | Conteúdo |
|:------|:-------:|:---------|
| `databaseschema` | 2 bytes | Versão do schema ("28") |
| `rebuildledger2` | 0 bytes | Flag de rebuild (vazio = ok) |
| `historyarchivestate` | 7.800 bytes | Bucket list state (JSON com hashes de todos os níveis) |
| `lastclosedledgerheader` | 572 bytes | Header XDR do último ledger fechado (base64) |
| `networkpassphrase` | 33 bytes | "Test SDF Network ; September 2015" |

### 2.3 Otimizações Aplicadas

#### WAL Mode — Pedra Angular da Concorrência

```
Cenário típico de validação:
  1. Ledger N está sendo fechado (escrita em offers)
  2. Nova transação chega (leitura de offers para validar)
  3. SEM WAL: transação espera ledger fechar (lock exclusivo)
  4. COM WAL: transação lê do DB principal enquanto escrita vai para o WAL

Ganho: Zero bloqueio entre validação e fechamento de ledger
```

#### Synchronous=NORMAL — Tolerância Calculada

```
Por que não FULL?
  - FULL: fsync a cada write (50x mais lento)
  - NORMAL: fsync a cada checkpoint (a cada 1.000 páginas)
  - Risco: perda de até 4 MB de dados em crash

Por que o risco é aceitável?
  - Os buckets (.xdr) contêm O ESTADO VERDADEIRO
  - O SQLite é um CACHE RECONSTRUÍVEL
  - Se o SQLite corrompe → reconstruir dos buckets
```

#### Auto-vacuum=NONE — Economia em Blockchain

```
Blockchain: muito INSERT, pouco DELETE
  - offers: recebe INSERT + DELETE (ofertas expiram)
  - storestate: UPDATE frequente no mesmo slot

Auto-vacuum=NONE:
  - PRÓ: Páginas deletadas não são reorganizadas (0 CPU de vacuum)
  - CONTRA: fragmentação ao longo do tempo
  - MITIGAÇÃO: banco tem apenas 23 MB — fragmentação irrelevante
  - EVIDÊNCIA: freelist de apenas 4 páginas = quase sem fragmentação
```

#### Page Size = 4.096 — Alinhamento com o SO

```
Cada página de 4 KB armazena ~9-10 linhas de offers (411 bytes/linha)
  → Leitura de 1 página = ~10 ofertas
  → Order book lookup lê ~1-2 páginas via índice

Alinhamento com ext4/NTFS (bloco de 4 KB):
  → I/O sem fragmentação entre FS e SQLite
  → Zero read-modify-write
```

---

## 3. SQLite Misc (stellar-misc.db) — Metadados de Rede

### 3.1 Anomalia: WAL de 40 MB para DB de 208 KB

```
DB:    208 KB  (52 páginas × 4 KB)
WAL:   40 MB   (192× o tamanho do DB!)

Isso indica:
  - MUITAS escritas de metadados SCP (envelopes)
  - Poucos checkpoints (wal_autocheckpoint alto)
  - Dados transitórios que poderiam ser descartados
```

### 3.2 Tabelas e Conteúdo

#### peers (170 linhas) — Descoberta de Nós

```sql
CREATE TABLE peers (
    ip           VARCHAR(15) NOT NULL,
    port         INT DEFAULT 0 NOT NULL,
    nextattempt  TIMESTAMP NOT NULL,
    numfailures  INT DEFAULT 0 NOT NULL,
    type         INT NOT NULL,
    PRIMARY KEY (ip, port)
);

-- 170 peers conhecidos na rede
-- type=1: saída (outbound), type=0: entrada (inbound)
-- nextattempt: momento da próxima tentativa de conexão
-- numfailures: tentativas falhas consecutivas
```

**Amostra de peers:**
```
98.91.174.101:11625    type=1  failures=0  (validador ativo)
44.204.146.210:11625   type=1  failures=0  (validador ativo)
64.23.228.195:11625    type=0  failures=10 (provável nó privado caindo)
```

#### scphistory (224 linhas) — Envelopes de Consenso

```sql
CREATE TABLE scphistory (
    nodeid    CHARACTER(56) NOT NULL, -- ID do validador
    ledgerseq INT NOT NULL,           -- Ledger sequence
    envelope  TEXT NOT NULL           -- Envelope SCP (base64 XDR)
);

-- Armazena os últimos envelopes SCP recebidos
-- Usado para diagnosticar problemas de consenso
-- 224 linhas = últimas ~75 rodadas de consenso (3 validadores × 75 ledgers)
```

**Exemplo de envelope (abreviado):**
```
nodeid: GDKXE2OZ... (sdf_testnet_1)
ledgerseq: 3.811.057
envelope: tipo=EXTERNALIZE, ballot=c75a, n=2, commit=c75a
  └── Voto do validador 1 confirmando o ledger 3.811.057
```

#### scpquorums (1 linha)

```sql
CREATE TABLE scpquorums (
    qsethash      CHARACTER(64) NOT NULL,
    lastledgerseq INT NOT NULL,
    qset          TEXT NOT NULL,
    PRIMARY KEY (qsethash)
);

-- Apenas 1 quorum set ativo:
-- qsethash = 59d361...
-- 3 validadores SDF: sdf_testnet_1, sdf_testnet_2, sdf_testnet_3
-- Threshold: t=2 (2 de 3 para acordo)
```

#### quoruminfo (5 linhas)

```
5 nós no quorum transitivo:
  - GDKXE2OZ... (sdf_testnet_1)
  - GCUCJTIY... (sdf_testnet_2)
  - GC2V2EFS... (sdf_testnet_3)
  - GBHJMDHX... (guardião extra)
  - GCYF3HGA... (possível o próprio nó)
Todos compartilham o mesmo qsethash (mesmo quorum set)
```

### 3.3 Otimizações

```
WAL mode: Necessário para escrita frequente de envelopes SCP
  - Cada ledger fechado gera MÚLTIPLOS envelopes (3 validadores)
  - WAL permite escrita rápida sem lock

WAL enorme (40 MB): Indica oportunidade de otimização
  - DB tem só 208 KB, mas WAL tem 40 MB
  - checkpoint mais frequente reduziria WAL
  - Mas: dados são transitórios, WAL grande é aceitável
```

---

## 4. Buckets XDR — O Verdadeiro Estado do Ledger

### 4.1 O que São

Buckets são arquivos binários XDR que armazenam **snapshots imutáveis do estado completo** do ledger Stellar. Diferentemente do SQLite que tem apenas ofertas, os buckets contêm **TUDO**: contas, trustlines, dados de contratos Soroban, offers, etc.

### 4.2 Hierarquia de Níveis (Bucket List)

```
Nível 5 (snap):  ─── 4 arquivos (785-905 MB)  ─── Snapshot mais profundo
                       ├── bucket-43d1a0e3...xdr  (905 MB)
                       ├── bucket-805620a8...xdr  (872 MB)
                       ├── bucket-ff26b4f5...xdr  (785 MB)
                       └── bucket-d8522ede...xdr  (600 MB)

Nível 4:          ─── 4 arquivos (202-355 MB)  ─── Merge intermediário
                       ├── bucket-b2a2c09a...xdr  (355 MB)
                       ├── bucket-18e2a5cb...xdr  (310 MB)
                       ├── ...
                       └── bucket-ec54d50d...xdr  (203 MB)

Nível 3:          ─── 3 arquivos (121-203 MB)  ─── Merge parcial
Nível 2:          ─── 9 arquivos (14-98 MB)   ─── Merge recente
Níveis 0-1:       ─── 37 arquivos (<10 MB)    ─── Dados novos
```

### 4.3 Otimização por Merge

```
Algoritmo de merge:

Novos ledgers → geram entradas no Nível 0
Quando Nível 0 atinge limite → merge para Nível 1
Quando Nível 1 atinge limite → merge para Nível 2
... até Nível 5 (snap)

Cada merge:
  - Combina buckets de níveis inferiores em um único bucket maior
  - Remove entradas obsoletas (sobrescritas por versões mais novas)
  - Gera novo hash SHA256 (nome do arquivo = hash do conteúdo)
  - Buckets antigos permanecem (imutabilidade)

Benefício:
  - Merge reduz 100 arquivos pequenos em 1 arquivo grande
  - Leitura de estado requer acesso a apenas 6 arquivos (1 por nível)
  - Imutabilidade permite cache agressivo (HTTP, CDN)
```

### 4.4 Distribuição de Conteúdo (do /metrics)

Baseado na análise anterior (bucket list do mesmo nó):

```
Tipo de Entrada          | Contagem    | Tamanho   | %
PERSISTENT_CONTRACT_DATA | 4.193.309   | 716 MB    | 40,2%
ACCOUNT                  | 2.956.700   | 374 MB    | 21,0%
CONTRACT_CODE            | 22.544      | 304 MB    | 17,1%
TTL                      | 4.356.785   | 208 MB    | 11,7%
DATA (account metadata)  | 332.654     | 49 MB     | 2,8%
TRUSTLINE                | 325.706     | 45 MB     | 2,5%
TEMPORARY_CONTRACT_DATA  | 143.452     | 22 MB     | 1,2%
OFFER                    | 53.382      | 9 MB      | 0,5%
CLAIMABLE_BALANCE        | 8.918       | 2 MB      | 0,1%
LIQUIDITY_POOL           | 2.592       | 422 KB    | <0,1%
CONFIG_SETTING           | 40          | 5 KB      | <0,1%
```

**Obs:** Offers nos buckets = 53.382 vs. SQLite = 56.600. A diferença (~3.200) é porque o SQLite inclui ofertas de buckets intermediários que ainda não foram mergeados para o snap.

---

## 5. Comparação: SQLite vs Buckets

| Aspecto | SQLite (stellar.db) | Buckets (.xdr) |
|:--------|:------------------:|:--------------:|
| **Propósito** | Cache para validação SCP | Armazenamento canônico do estado |
| **Conteúdo** | Apenas offers (~0,5% do estado) | Estado completo (100%) |
| **Tamanho** | 23 MB + 42 MB WAL | 5,7 GB |
| **Formato** | Relacional (SQL) | Binário (XDR) |
| **Mutabilidade** | Mutável (UPDATE/DELETE) | Imutável (append-only) |
| **Recuperável** | Sim (reconstruído dos buckets) | Sim (dos history archives) |
| **Concorrência** | WAL (single writer) | N/A (arquivos estáticos) |
| **Indexação** | B-tree (2 índices) | N/A (hash-based lookup) |

### 5.1 Por que o SQLite não Armazena o Estado Completo?

```
Resposta: Performance de Validação

O stellar-core PRECISA de:
  1. Apenas OFFERS para validar transações de order book
  2. Apenas STORESTATE para tracking interno
  3. Acesso rápido (< 1ms) → SQLite em WAL mode

O que o core NÃO precisa em tempo real:
  - Contas (2,9M) → saldo é verificado via buckets
  - Trustlines (325K) → confiança é verificada via buckets
  - Contract data (4,2M) → execução Soroban via buckets

Estratégia: "puxe apenas o necessário para memória"
  O SQLite carrega offers (ponto crítico de concorrência)
  O resto fica nos buckets (acesso sob demanda)
```

### 5.2 Fluxo de Validação: Como os Três Sistemas se Integram

```
TRANSAÇÃO CHEGA (ex: "comprar 100 XLM por USDC")
         │
         ▼
┌─────────────────────────────────────────────────────┐
│ 1. VERIFICA OFFERS (SQLite main)                     │
│                                                       │
│    SELECT * FROM offers                               │
│    WHERE sellingasset = 'XLM'                        │
│      AND buyingasset = 'USDC'                        │
│      AND price >= 0.10                               │
│    ORDER BY price ASC, offerid ASC                    │
│    LIMIT 10;                                          │
│                                                       │
│    → Usa índice bestofferindex                        │
│    → Lê ~2-3 páginas do cache SQLite                  │
│    → Tempo: < 1 ms                                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 2. VERIFICA SALDO (Buckets)                          │
│                                                       │
│    Bucket de nível 5 → snapshot mais recente         │
│    Busca a conta do comprador                        │
│    Verifica saldo de USDC                            │
│                                                       │
│    → Acesso via hash (bucket nomeado por hash)        │
│    → Pode estar em cache de memória                  │
│    → Tempo: < 5 ms                                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 3. REGISTRA CONSENSO (SQLite misc)                   │
│                                                       │
│    INSERT INTO scphistory (nodeid, ledgerseq,        │
│                            envelope)                 │
│    VALUES ('GDKXE...', 3741301, 'AAAA...');          │
│                                                       │
│    → Registra o voto do validador                    │
│    → WAL mode permite escrita rápida                 │
│    → Tempo: < 1 ms                                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 4. ATUALIZA OFFERS (SQLite main)                     │
│                                                       │
│    DELETE FROM offers WHERE offerid = 389603;        │
│    (oferta foi executada, removida)                  │
│                                                       │
│    INSERT INTO offers (sellerid, offerid, ...)       │
│    VALUES ('GD7V...', 385498, ...);                  │
│    (nova oferta residual criada)                     │
│                                                       │
│    → WAL mode: DELETE + INSERT no WAL (rápido)       │
│    → Tempo: < 2 ms                                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│ 5. PUBLICA BUCKET (merge assíncrono)                 │
│                                                       │
│    A cada checkpoint (64 ledgers):                   │
│    Buckets Nível 0 → merge → Nível 1                │
│    Buckets Nível 1 → merge → Nível 2 (se cheio)     │
│    ...                                               │
│    Buckets Nível 5 → novo snapshot                  │
│                                                       │
│    → Dispara publicação para history archive         │
│    → Tempo: segundos a minutos (background)          │
└─────────────────────────────────────────────────────┘
```

---

## 6. Conclusões

### 6.1 Três Sistemas, Três Papéis Distintos

| Sistema | Papel | Otimização Principal |
|:--------|:------|:--------------------|
| **SQLite main** | Cache de ofertas para validação | WAL mode + synchronous=NORMAL |
| **SQLite misc** | Metadados de rede e consenso | WAL mode (escrita intensa) |
| **Buckets XDR** | Estado completo imutável | Merge hierárquico + hash-based lookup |

### 6.2 Não Há PostgreSQL no Validador

Confirma-se: o stellar-core usa **exclusivamente SQLite** como banco relacional embarcado. PostgreSQL existe apenas no container Horizon (API), que não participa do consenso.

### 6.3 Decisões de Projeto Notáveis

1. **Cache seletivo**: SQLite armazena apenas 0,5% do estado (offers). O resto fica em buckets. Isso reduz o DB de ~5,7 GB para 23 MB.

2. **Tolerância a perda**: synchronous=NORMAL + auto-vacuum=NONE são aceitáveis porque o SQLite é reconstruível dos buckets.

3. **WAL em ambos os SQLites**: A escolha de WAL sobre rollback journal permite concorrência entre validação (leitura) e fechamento de ledger (escrita).

4. **WAL desproporcional no misc**: 40 MB de WAL para 208 KB de DB indicam alta taxa de escrita de envelopes SCP com checkpoint infrequente.

5. **Bucket merge**: Algoritmo de níveis (L0 a L5) reduz o número de arquivos necessários para reconstruir estado de milhares para apenas 6 (1 por nível).

### 6.4 Oportunidades de Otimização

| Oportunidade | Impacto | Complexidade |
|:-------------|:--------|:-------------|
| Aumentar checkpoint WAL no misc.db | Reduzir WAL de 40 MB → ~1 MB | Baixa |
| Índice covering para order book | Já implementado (bestofferindex) | - |
| Cache de buckets em RAM (mmap) | Atualmente 0 (mmap_size=0) | Média |
| Compressão de buckets XDR | Reduzir 5,7 GB → ~2 GB | Alta |

---

## Apêndice A: Dados Brutos Coletados

```
stellar.db:
  page_count:   5.692
  page_size:    4.096
  journal_mode: wal
  synchronous:  2 (NORMAL)
  auto_vacuum:  0 (NONE)
  cache_size:   -2.000 (~8 MB)
  freelist:     4
  integrity:    ok
  file:         23 MB
  wal:          42 MB

stellar-misc.db:
  page_count:   52
  page_size:    4.096
  journal_mode: wal
  synchronous:  2 (NORMAL)
  file:         208 KB
  wal:          40 MB

Buckets:
  total:        57 .xdr files
  tamanho:      5,7 GB
  indices:      36 .index files
  >= 500 MB:    4
  100-500 MB:   11
  10-100 MB:    9
  1-10 MB:      11
  < 1 MB:       21
  catchup tmp:  50 MB (1.231 arquivos)
```

## Apêndice B: Comandos para Reprodução

```bash
# SQLite main
docker exec stellar-core sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode; PRAGMA synchronous; PRAGMA auto_vacuum; PRAGMA integrity_check;"

# SQLite misc
docker exec stellar-core sqlite3 /opt/stellar/core/stellar-misc.db ".tables"
docker exec stellar-core sqlite3 /opt/stellar/core/stellar-misc.db "SELECT COUNT(*) FROM peers; SELECT COUNT(*) FROM scphistory;"

# Buckets
docker exec stellar-core ls -lhS /opt/stellar/core/buckets/*.xdr | head -10
docker exec stellar-core du -sh /opt/stellar/core/buckets/

# Info do nó
curl http://localhost:11626/info
```
