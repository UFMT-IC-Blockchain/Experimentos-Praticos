# Docker Stellar Core + Horizon — MainNet

**Propósito:** Estudo de técnicas de otimização de armazenamento de dados em ambientes blockchain
**Rede:** Stellar MainNet ("Public Global Stellar Network ; September 2015")
**Arquitetura:** 2 containers separados (stellar-core + stellar-horizon)
**Baseado em:** `Docker-Core-Horizon-Separado` (TestNet), configurado para MainNet

---

## 1. Contexto do Estudo

Este setup foi criado para investigar **como os dados são armazenados, replicados e processados** em um nó completo da rede Stellar (MainNet). Diferente de blockchains como Bitcoin (UTXO) ou Ethereum (state trie), a Stellar usa um modelo de **bucket list** baseado em hashes encadeados com merges logarítmicos — um design que tem implicações diretas na eficiência de armazenamento.

### 1.1. Perguntas de pesquisa

1. **Duplicação de dados**: Por que o Horizon precisa de seu próprio captive core? Quanto armazenamento é "desperdiçado" vs. necessário?
2. **Bucket list vs. banco relacional**: Como o stellar-core comprime o estado em buckets XDR vs. como o Horizon o expande em 33 tabelas PostgreSQL?
3. **WAL (Write-Ahead Log)**: Qual o custo de escrita durante o catch-up vs. operação estável?
4. **MainNet vs. TestNet**: Qual a diferença real de volume de dados entre as duas redes?

---

## 2. Arquitetura de Armazenamento (Stellar)

### 2.1. Bucket List (stellar-core)

O stellar-core não armazena o estado em um banco de dados tradicional. Em vez disso, usa uma **bucket list**:

```
Ledger N-1          Ledger N           Ledger N+1
   │                   │                   │
   ▼                   ▼                   ▼
┌──────────┐      ┌──────────┐       ┌──────────┐
│ Bucket 0 │──────│ Bucket 0'│───────│ Bucket 0"│  ← Nível 0 (fresco, pequeno)
├──────────┤      ├──────────┤       ├──────────┤
│ Bucket 1 │──────│ Bucket 1'│───────│ Bucket 1"│  ← Nível 1 (merge a cada 64 ledgers)
├──────────┤      ├──────────┤       ├──────────┤
│    ...   │      │    ...   │       │    ...   │
├──────────┤      ├──────────┤       ├──────────┤
│ Bucket 10│──────│ Bucket 10'│──────│ Bucket 10"│ ← Nível 10 (snapshot completo)
└──────────┘      └──────────┘       └──────────┘
     │                   │                   │
     └───────────────────┴───────────────────┘
                         │
                         ▼
              History Archive (SDF)
         https://history.stellar.org/prd/core-live/
```

**Características:**
- Cada bucket é um arquivo XDR imutável (hash SHA256 do conteúdo = nome)
- Nível 0: buckets pequenos (~25 KB) — apenas as mudanças do ledger atual
- Nível 10: snapshot completo do estado (~785 MB na MainNet)
- A cada 64 ledgers, buckets de níveis inferiores são mergeados em superiores
- Buckets antigos são descartados (só os atuais são mantidos)

**Otimização de armazenamento:** Buckets compartilham dados via hashes. Se um bucket não muda entre snapshots, seu hash permanece o mesmo e ele é reutilizado (deduplicação implícita).

### 2.2. Bancos de Dados

| Componente | Tecnologia | Conteúdo | Tamanho estimado (MainNet) |
|-----------|-----------|----------|---------------------------|
| Core Node | SQLite (WAL) | Ledger headers, transações, bucket metadata | ~200 MB + buckets |
| Captive Core | SQLite (WAL) | Idêntico ao Core Node (duplicado) | ~200 MB + buckets |
| Horizon | PostgreSQL (WAL) | Dados processados em 33 tabelas | ~50-150 GB |
| Buckets (Core) | Arquivos XDR + index | Estado completo da blockchain | ~50 GB |
| Buckets (Captive) | Arquivos XDR + index | Idêntico ao Core (duplicado) | ~50 GB |

### 2.3. Pipeline de Dados

```
History Archive SDF ───► Core Node ───► SQLite (estado atual)
                              │
                              ├──► P2P consensus (SCP)
                              │
History Archive SDF ───► Captive Core ───► SQLite (metadados)
                              │
                              ▼
                         Horizon ───► PostgreSQL (33 tabelas)
```

---

## 3. Diferenças TestNet vs. MainNet (Impacto no Armazenamento)

| Característica | TestNet | MainNet | Impacto |
|---------------|---------|---------|---------|
| **Network passphrase** | `Test SDF Network ; September 2015` | `Public Global Stellar Network ; September 2015` | Nenhum (só string) |
| **Validadores** | 3 (SDF) | 21 (SDF + LOBSTR + SatoshiPay + Blockdaemon + etc.) | +P2P traffic |
| **HOME_DOMAINS** | 1 (`testnet.stellar.org`) | 7 entidades | +config |
| **History archive** | `core-testnet/core_testnet_00{N}` | `core-live/core_live_00{N}` | Endpoint |
| **Buckets (estado)** | ~4,4 GB | ~50 GB estimado | **~10x maior** |
| **PostgreSQL (Horizon)** | ~4 GB (parcial) | ~50-150 GB estimado | **~25x maior** |
| **Contas (accounts)** | ~2,9 milhões | ~7-8 milhões estimado | Maior volume |
| **Transações** | ~236 mil ingeridas | Milhões | Muito maior |
| **Soroban (contratos)** | ~4.668 códigos | Muito mais | State佔比 maior |

### 3.1. Por que MainNet é tão maior?

1. **Idade**: MainNet roda desde 2015; TestNet foi resetada múltiplas vezes
2. **Adoção real**: MainNet tem transações financeiras reais, emissores de ativos, ancoras
3. **Soroban**: Contratos inteligentes (Soroban) na MainNet têm adoção muito maior que TestNet
4. **Volume de operações**: MainNet processa ~5-10x mais transações por ledger

---

## 4. Modificações Realizadas (TestNet → MainNet)

### 4.1. `docker-compose.yml`

```diff
- container_name: stellar-core
+ container_name: stellar-core-mainnet
- container_name: stellar-horizon
+ container_name: stellar-horizon-mainnet
- network: stellar-network (172.20.0.0/24)
+ network: mainnet-network (172.21.0.0/24)
- ports: 11625-11626
+ ports: 11627-11628 (evitar conflito com TestNet)
- ports: 8000
+ ports: 8001 (evitar conflito)
- NETWORK=testnet
+ NETWORK=pubnet
- volume: pgdata:/var/lib/postgresql/14/main
+ volume: pgdata:/var/lib/postgresql/16/main
```

### 4.2. `stellar-core/stellar-core.cfg`

```diff
- NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
+ NETWORK_PASSPHRASE="Public Global Stellar Network ; September 2015"
- 3 validators SDF testnet
+ 21 validators (SDF + LOBSTR + SatoshiPay + Blockdaemon + etc.)
- HOME_DOMAIN = "testnet.stellar.org"
+ 7 HOME_DOMAINs (lobstr.co, publicnode.org, satoshipay.io, ...)
- HISTORY → core_testnet_00{N}
+ HISTORY → core_live_00{N}
```

### 4.3. `stellar-horizon/stellar-captive-core.cfg`

Mesmas alterações do core.cfg (network passphrase, validators, history).

### 4.4. `stellar-horizon/horizon.env`

```diff
- # NETWORK=testnet define automaticamente (comentário)
- # HISTORY_ARCHIVE_URLS omitido (comentário)
+ export NETWORK_PASSPHRASE="Public Global Stellar Network ; September 2015"
+ export HISTORY_ARCHIVE_URLS="https://history.stellar.org/prd/core-live/core_live_001"
```

### 4.5. Entrypoints

Mensagens de echo atualizadas para refletir "MainNet" e a passphrase correta.

---

## 5. Observações sobre Otimização de Armazenamento

### 5.1. Duplicação Core vs. Captive Core

O Horizon gerencia seu próprio stellar-core (captive core) que baixa buckets **independentemente** do core node principal. Isso significa:

- **Custo**: ~100 GB duplicados (50 GB core + 50 GB captive)
- **Benefício**: Isolamento total — a ingestão do Horizon não impacta o consenso SCP
- **Trade-off**: Aceitável para nós de API; inviável para dispositivos com pouco armazenamento

**Possível otimização:** Configurar o captive core para reutilizar os buckets do core node via bind mount read-only. Porém, o stellar-core não suporta compartilhamento de buckets entre instâncias por questões de consistência.

### 5.2. PostgreSQL vs. SQLite

| Aspecto | SQLite (Core) | PostgreSQL (Horizon) |
|---------|--------------|---------------------|
| Tamanho | ~200 MB (dados + WAL) | ~50-150 GB (dados + índices) |
| Tipo de dado | Estado serializado (XDR) | Dados relacionais normalizados |
| Índices | Poucos (chave primária) | Muitos (consultas API) |
| WAL | ~40-44 MB durante catchup | ~400 MB+ durante catchup |

**Otimização observada na TestNet:** A tabela `accounts_signers` é a maior do PostgreSQL (1.4 GB com índices), superando a tabela `accounts` (873 MB). Isso ocorre porque contas multi-sig têm múltiplos signers, cada um com seu próprio registro.

### 5.3. Impacto do Soroban no Armazenamento

Na TestNet, os dados de contratos Soroban já dominam o estado:
- `PERSISTENT_CONTRACT_DATA`: 740 MB (40,2% do estado total)
- `CONTRACT_CODE`: 326 MB (17,7%)
- `TTL` (Time-To-Live): 217 MB (11,8%)

**Total Soroban: ~58% do estado.** Na MainNet, essa proporção tende a ser ainda maior.

### 5.4. WAL (Write-Ahead Log) como Indicador

O tamanho do WAL durante o catch-up revela a intensidade de escrita:
- **SQLite WAL (Core)**: 44 MB — muitas transações de ledger sendo aplicadas
- **SQLite WAL (Captive)**: 40 MB — mesmo processo, paralelo
- **PostgreSQL WAL**: 417 MB — 16 MB por segmento, ~26 segmentos

Após o catch-up, o WAL tende a estabilizar em tamanhos menores (~10-20% do pico).

---

## 6. Como usar

### Build e start

```bash
cd Docker-MainNet
docker-compose build --no-cache
docker-compose up -d
```

### Verificar status

```bash
# Core (portas 11627-11628)
curl http://localhost:11628/info

# Horizon (porta 8001)
curl http://localhost:8001/
```

### Parar

```bash
docker-compose down
```

### Limpar dados (começar do zero)

```bash
docker-compose down -v
docker-compose up -d
```

---

## 7. Portas

| Container | Porta | Externo | Descrição |
|-----------|:-----:|:-------:|-----------|
| stellar-core-mainnet | 11627 | Sim | P2P (conexão com validadores MainNet) |
| stellar-core-mainnet | 11628 | Sim | HTTP (admin, métricas) |
| stellar-horizon-mainnet | 8001 | Sim | HTTP público (nginx → Horizon API) |
| stellar-horizon-mainnet | 5432 | Não | PostgreSQL (apenas interno) |
| stellar-horizon-mainnet | 11725 | Não | Captive Core P2P (interno) |
| stellar-horizon-mainnet | 11726 | Não | Captive Core HTTP (interno) |

---

## 8. Volumes

| Volume | Container | Caminho | Conteúdo estimado |
|--------|-----------|---------|------------------|
| core-data | stellar-core-mainnet | /opt/stellar/core | SQLite + Buckets (~50 GB) |
| horizon-data | stellar-horizon-mainnet | /opt/stellar/horizon | Captive Core SQLite + Buckets (~50 GB) |
| pgdata | stellar-horizon-mainnet | /var/lib/postgresql/16/main | PostgreSQL (~50-150 GB) |

---

## 9. Referências

- [Stellar Bucket List Architecture](https://developers.stellar.org/docs/learn/fundamentals/bucket-list)
- [Stellar Core Config](https://developers.stellar.org/docs/run-api-server/setup/config)
- [Stellar Horizon Architecture](https://developers.stellar.org/docs/run-api-server/setup)
- [SDF Network Parameters](https://developers.stellar.org/docs/validators/list)
