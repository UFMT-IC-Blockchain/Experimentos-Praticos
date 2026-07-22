# Relatório de Atividades — 16/07/2026

**Disciplina:** Mestrado — Blockchain  
**Objetivo do Experimento:** Monitoramento sistemático da mempool, vazão de transações e comportamento da rede Stellar Testnet em três escalas temporais (30, 100 e 500 ledgers), com decodificação de falhas via XDR e geração de relatórios analíticos com gráficos interativos.

---

## 1. Atividades Realizadas

### 1.1 Experimento 1: Monitoramento de 30 Ledgers (Mempool e Vazão)

**Horário:** ~21:32 BRT  
**Ledgers:** L#3646628 a L#3646657 (~150 segundos)

Foi realizado o primeiro monitoramento sistemático da mempool, coletando dados via API Horizon (`localhost:8000`) e API HTTP do Stellar Core (`localhost:11626`). Os dados foram processados e armazenados em JSON e CSV, com categorização de falhas via decodificação XDR.

**Métricas coletadas por ledger:**
- Transações OK e FAIL
- Operações executadas e propostas no TxSet
- Fee pool acumulado
- Consumo de memória dos processos

**Resultados principais:**
- **236 OK**, **42 FAIL** — sucesso de **84,9%**
- Vazão média: **1,57 tx/s**
- Utilização do TxSet: **6,8%** (baixa — sem congestão)
- Fee pool: **+0,4524 XLM** (crescimento linear)
- RAM total do container: **~6,91 GiB** (44,4% de 15,56 GiB)

**Falhas categorizadas (4 tipos):** PAYMENT_NOTRUST (dominante), PAYMENT_NODESTINATION, PAYMENT_UNDERFUNDED, SOROBAN_TRAPPED, txFeeBumpInnerFailed.

**Arquivos gerados:** `Monitoramento-30-ledgers/` — `chart-ledgers.html`, `ledger-data.json`, `ledger-data.csv`, `falhas-categorizadas.json`, `relatorio-mempool.md`.

### 1.2 Documentação do Fluxo de Transação (Relatorio-Transacao-Submetida)

Foi produzido um relatório detalhado documentando o ciclo de vida completo de uma transação submetida via cliente local (`@stellar/stellar-sdk`) até a persistência no PostgreSQL. A transação rastreada foi um pagamento de **99 XLM** (ledger 3646201), percorrendo 9 etapas:

1. Construção e assinatura no cliente Node.js
2. Submissão ao Horizon (`POST /transactions`)
3. Validação pelo Captive Core (sequência, assinatura, saldo, time bounds)
4. Propagação para a rede P2P (porta 11725)
5. Consenso SCP (4 fases com 3/3 validadores SDF)
6. Fechamento do ledger (11 OK + 2 FAIL)
7. Retorno dos metadados via pipe (fd:3)
8. Persistência no PostgreSQL (3 tabelas de histórico + accounts)
9. Confirmação HTTP 200 com ResultXDR

**Documento gerado:** `Relatorio-Transacao-Submetida-Horizon-Local.md`

### 1.3 Experimento 2: Monitoramento de 100 Ledgers

**Horário:** ~22:10–22:23 BRT  
**Ledgers:** L#3647282 a L#3647381 (~8 minutos)

Coleta automatizada dos mesmos indicadores do Experimento 1, porém em escala estendida. Dados agrupados em **10 grupos de 10 ledgers** para análise de tendências.

**Resultados:**
- **765 OK**, **171 FAIL** — sucesso de **81,7%**
- Média de **7,7 OK** e **1,7 FAIL**/ledger
- Fee pool: **+6,2009 XLM** (crescimento linear)
- Backlog: máximo de **504 ops**

**Falhas categorizadas (7 tipos):** PAYMENT_NOTRUST 61%, PAYMENT_NODESTINATION 16%, PAYMENT_UNDERFUNDED 11%, SOROBAN_TRAPPED 8%, DECODE_ERR 2%, OP_TOOMANYSUBENTRIES 1%, OP_CREATEACCOUNT 1%.

**Arquivos gerados:** `Monitoramento-100-ledgers/` — `chart-ledgers-100.html`, `dados-100-ledgers.json`, `RELATORIO.md`.

### 1.4 Experimento 3: Monitoramento de 500 Ledgers

**Horário:** ~22:10–22:23 BRT  
**Ledgers:** L#3646525 a L#3647024 (~42 minutos)

Monitoramento estendido para análise de comportamento de longo prazo, especialmente o acúmulo de backlog e a evolução das taxas de falha. Dados agrupados em **17 grupos de 30 ledgers**.

**Resultados:**
- **4.173 OK**, **839 FAIL** — sucesso de **83,3%**
- Média de **8,35 OK** e **1,68 FAIL**/ledger
- Vazão: **1,67 tx/s**
- Backlog: **2.829 ops** (crescimento contínuo — entrada > processamento)
- Fee pool: **+15,9239 XLM**

**Falhas categorizadas (9 tipos):** PAYMENT_NOTRUST 61%, PAYMENT_NODESTINATION 16%, PAYMENT_UNDERFUNDED 10%, DECODE_ERR 5%, SOROBAN_TRAPPED 5%, OP_TYPE_REVOKESPONSORSHIP 2%, OP_TYPE_MANAGESELLOFFER 1%, OP_TOOMANYSUBENTRIES 0,5%, OP_TYPE_CHANGETRUST 0,2%.

**Descoberta crítica:** O backlog cresceu de **5 para 2.829 ops** durante o período, indicando que a taxa de geração de transações superou consistentemente a capacidade de processamento da rede testnet.

**Arquivos gerados:** `Monitoramento-500-ledgers/` — `chart-ledgers-500.html`, `chart-ledgers-500-dividido.html`, `dados-500-ledgers.json`, `RELATORIO.md`.

### 1.5 Geração de Gráficos Interativos (Chart.js)

Para cada experimento, foram gerados arquivos HTML com **7 gráficos interativos** utilizando Chart.js:

1. **OK vs FAIL** — barras empilhadas por ledger
2. **TxSet vs Executadas** — barras comparativas
3. **Taxa de Sucesso (%)** — linha com área
4. **Fee Pool** — linha acumulada
5. **Fluxo na Mempool** — barras empilhadas (entrada, confirmadas, rejeitadas)
6. **Backlog** — 3 linhas (proposto, processado, backlog)
7. **Falhas por tipo** — linhas múltiplas por categoria

Os gráficos do experimento de 500 ledgers foram gerados em duas versões: tela única com scroll horizontal (15000px) e versão dividida em 5 grupos de 100 ledgers.

### 1.6 Decodificação de Falhas via XDR

Todas as transações com falha foram decodificadas utilizando:
- `stellar-core print-xdr --base64` para decodificação do campo `result_xdr`
- Módulo `xdr` da biblioteca `@stellar/stellar-sdk` para interpretação programática

As categorias de falha foram extraídas e contabilizadas para cada experimento, permitindo a geração de gráficos de distribuição e tabelas comparativas.

### 1.7 Elaboração de Relatórios

Foram produzidos os seguintes documentos para cada experimento:

- **RELATORIO.md** (100 e 500 ledgers): Relatórios completos com tabelas, gráficos Mermaid agrupados e análises detalhadas
- **Relatorio-Transacao-Submetida-Horizon-Local.md**: Documentação do fluxo ponta-a-ponta de uma transação
- **relatorio-mempool.md**: Análise focada na mempool (30 ledgers)
- **O presente documento (Relatorio-Dia.md)**: Consolidação acadêmica das atividades do dia

### 1.8 Controle de Versão e Organização

- **Reorganização:** Os arquivos foram movidos de diretório único para subdiretórios por tipo de monitoramento (`Monitoramento-30-ledgers/`, `Monitoramento-100-ledgers/`, `Monitoramento-500-ledgers/`)
- **Commits realizados:**
  - `ce01edc` — Adiciona experimentos do dia 16/07/2026 (arquivos iniciais)
  - `12f26df` — Reorganiza em subdiretórios por tipo de monitoramento
  - `c8cbc40` — Adiciona relatórios e atualiza charts

---

## 2. Estrutura Final dos Arquivos Gerados

```
Experimentos-Julho-2026/
└── 2026-07-16/
    ├── Relatorio-Dia.md                              # Presente documento
    ├── Relatorio-Transacao-Submetida-Horizon-Local.md # Fluxo de transação (11 KB)
    ├── Monitoramento-30-ledgers/
    │   ├── relatorio-mempool.md                      # Análise da mempool (7,6 KB)
    │   ├── chart-ledgers.html                        # Gráficos interativos (37 KB)
    │   ├── ledger-data.json                          # Dados brutos (9,1 KB)
    │   ├── ledger-data.csv                           # Dados em CSV (1,2 KB)
    │   └── falhas-categorizadas.json                 # Falhas decodificadas (5,8 KB)
    ├── Monitoramento-100-ledgers/
    │   ├── RELATORIO.md                              # Relatório completo (12,8 KB)
    │   ├── chart-ledgers-100.html                    # Gráficos interativos (16,3 KB)
    │   ├── dados-100-ledgers.json                    # Dados brutos (54,4 KB)
    │   └── Relatorio-Dia.md                          # Presente documento
    └── Monitoramento-500-ledgers/
        ├── RELATORIO.md                              # Relatório completo (15,2 KB)
        ├── chart-ledgers-500.html                    # Gráficos scroll horizontal (158 KB)
        ├── chart-ledgers-500-dividido.html           # Gráficos em 5 grupos (78,8 KB)
        ├── dados-500-ledgers.json                    # Dados brutos (309,7 KB)
        └── Relatorio-Dia.md                          # Presente documento
```

---

## 3. Observações e Resultados

- **Taxa de sucesso consistente:** Todos os experimentos apresentaram sucesso entre **81,7% e 84,9%**, indicando ser este o baseline da testnet sob as condições experimentais.
- **PAYMENT_NOTRUST domina falhas:** ~61% em todos os experimentos — sugere problema sistemático de configuração de trust lines nas contas de teste.
- **Backlog crescente:** O experimento de 500 ledgers revelou backlog de **2.829 ops**, demonstrando que a geração de transações superou a capacidade de processamento da rede durante todo o período.
- **Mempool subutilizada:** Apesar do backlog, apenas **6,8%** da capacidade do TxSet (200 ops/ledger) foi utilizada.
- **Fee pool linear:** Nenhum indício de Surge Pricing — as taxas base de 100 stroops não foram alteradas.
- **Consumo de memória estável:** Container manteve ~6,91 GiB de RAM (44,4%), com Node e Captive Core consumindo ~2,8 GB cada.

---

> **Relatório gerado em:** 16/07/2026  
> **Container:** stellar/quickstart:testing (testnet)  
> **Experimentos:** 30, 100 e 500 ledgers consecutivos  
> **Total de transações analisadas:** ~5.400 operaçõe
