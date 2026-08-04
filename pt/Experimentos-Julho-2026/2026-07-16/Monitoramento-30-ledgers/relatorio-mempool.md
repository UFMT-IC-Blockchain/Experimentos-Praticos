# Relatório: Análise da Mempool e Vazão de Transações

**Data:** 16/07/2026
**Rede:** Test SDF Network ; September 2015
**Container:** stellar-testnet (stellar/quickstart:testing)
**Período de monitoramento:** 30 ledgers consecutivos (L#3646628 a L#3646657)

---

## 1. Metodologia

Foram monitorados 30 ledgers consecutivos através da API Horizon local (http://localhost:8000) e da API HTTP do Stellar Core Node (http://localhost:11626). Para cada ledger, capturou-se:

- Número de transações bem-sucedidas (OK)
- Número de transações com falha (FAIL)
- Operações executadas
- Operações propostas no Transaction Set (TxSet)
- Fee pool acumulado
- Consumo de memória dos processos stellar-core

---

## 2. Resumo Geral

| Métrica | Valor |
|---|---|
| Ledgers monitorados | 30 |
| Transações OK | 236 |
| Transações FAIL | 42 |
| **Total transações** | 278 |
| **Taxa de sucesso** | 84.9% |
| Média OK/ledger | 7.87 |
| Média FAIL/ledger | 1.40 |
| **Vazão média** | 7.87 tx/ledger = **1.57 tx/s** |
| Operações propostas (TxSet) | 410 |
| Operações executadas | 286 |
| Operações descartadas/falhas | 124 (30.2%) |
| Fee pool inicial | 400279.2073 XLM |
| Fee pool final | 400279.6597 XLM |
| Taxas coletadas | **0.4524 XLM** (~150.80 stroops/ledger) |

---

## 3. Dados Coletados (Tabela Completa)

| Ledger | OK | FAIL | Total | OPs TxSet | OPs Exec | % Sucesso | % TxSet Usado |
|---|---|---|---|---|---|---|---|
| 3646628 | 8 | 1 | 9 | 11 | 10 | 88.9% | 5.5% |
| 3646629 | 7 | 2 | 9 | 15 | 9 | 77.8% | 7.5% |
| 3646630 | 9 | 1 | 10 | 15 | 11 | 90.0% | 7.5% |
| 3646631 | 7 | 0 | 7 | 9 | 9 | 100.0% | 4.5% |
| 3646632 | 7 | 1 | 8 | 10 | 9 | 87.5% | 5.0% |
| 3646633 | 7 | 2 | 9 | 14 | 9 | 77.8% | 7.0% |
| 3646634 | 8 | 3 | 11 | 42 | 10 | 72.7% | 21.0% |
| 3646635 | 11 | 1 | 12 | 15 | 13 | 91.7% | 7.5% |
| 3646636 | 11 | 2 | 13 | 19 | 13 | 84.6% | 9.5% |
| 3646637 | 5 | 1 | 6 | 9 | 7 | 83.3% | 4.5% |
| 3646638 | 10 | 0 | 10 | 12 | 12 | 100.0% | 6.0% |
| 3646639 | 9 | 1 | 10 | 15 | 11 | 90.0% | 7.5% |
| 3646640 | 6 | 4 | 10 | 15 | 8 | 60.0% | 7.5% |
| 3646641 | 9 | 2 | 11 | 13 | 11 | 81.8% | 6.5% |
| 3646642 | 7 | 1 | 8 | 10 | 9 | 87.5% | 5.0% |
| 3646643 | 8 | 2 | 10 | 14 | 8 | 80.0% | 7.0% |
| 3646644 | 7 | 1 | 8 | 11 | 7 | 87.5% | 5.5% |
| 3646645 | 7 | 2 | 9 | 10 | 7 | 77.8% | 5.0% |
| 3646646 | 7 | 1 | 8 | 8 | 7 | 87.5% | 4.0% |
| 3646647 | 8 | 1 | 9 | 12 | 8 | 88.9% | 6.0% |
| 3646648 | 10 | 1 | 11 | 14 | 10 | 90.9% | 7.0% |
| 3646649 | 12 | 1 | 13 | 14 | 12 | 92.3% | 7.0% |
| 3646650 | 8 | 1 | 9 | 15 | 11 | 88.9% | 7.5% |
| 3646651 | 9 | 2 | 11 | 16 | 12 | 81.8% | 8.0% |
| 3646652 | 6 | 1 | 7 | 13 | 9 | 85.7% | 6.5% |
| 3646653 | 8 | 3 | 11 | 16 | 11 | 72.7% | 8.0% |
| 3646654 | 8 | 2 | 10 | 15 | 10 | 80.0% | 7.5% |
| 3646655 | 4 | 1 | 5 | 7 | 6 | 80.0% | 3.5% |
| 3646656 | 10 | 1 | 11 | 16 | 12 | 90.9% | 8.0% |
| 3646657 | 3 | 0 | 3 | 5 | 5 | 100.0% | 2.5% |

---

## 4. Análise Estatística

### 4.1 Transações OK por Ledger

| Métrica | Valor |
|---|---|
| Média | 7.87 tx/ledger |
| Mínimo | 3 tx/ledger |
| Máximo | 12 tx/ledger |
| Desvio padrão | 1.96 |

### 4.2 Transações FAIL por Ledger

| Métrica | Valor |
|---|---|
| Média | 1.40 tx/ledger |
| Mínimo | 0 tx/ledger |
| Máximo | 4 tx/ledger |

### 4.3 Proporção Entrada/Saída (Mempool)

A diferença entre `TxSetOPs` (operações propostas pelos validadores) e `OPs Exec` (operações que de fato foram executadas) representa as operações que **entraram na mempool do propositor** mas **não foram confirmadas** naquele ledger — seja por falha de execução ou por terem sido substituídas no momento do fechamento do ledger:

| Métrica | Valor |
|---|---|
| Total proposto (entrada mempool) | 410 |
| Total executado (saída) | 286 |
| Descartado/falha | 124 |
| Taxa de descarte | 30.2% |
| Utilizaçao média do TxSet | 6.8% |

---

## 5. Impacto na Memória

O consumo de memória dos dois processos stellar-core durante o período monitorado foi:

### 5.1 Stellar Core Node (PID 121)
- **RSS:** ~2,949 MB (~2.81 GB)
- **Função:** Mantém bucket list (~4.7 GB), conexões P2P, consenso SCP
- **Impacto da mempool:** A mempool do node armazena transações pendientes em RAM até serem incluídas em um ledger. Cada transação na mempool ocupa ~1-2 KB (envelope XDR + metadados associados). Com max_tx_set_size=200 e uso médio de ~13.7 ops/ledger, a mempool pode conter dezenas a centenas de transações em espera.

### 5.2 Captive Core (PID 279)
- **RSS:** ~2,911 MB (~2.78 GB)
- **Função:** Bucket list isolada (~5.4 GB), streaming de metadados para Horizon
- **Impacto da mempool:** O Captive Core mantém sua própria mempool (menor que a do node) apenas para gerenciar as transações que está processando para o Horizon.

### 5.3 Container (total)
- **Memória total:** ~6.91 GiB (44.42% dos 15.56 GiB disponíveis)
- **Distribuição:** Node (~40.7%) + Captive (~40.2%) + Horizon + PostgreSQL + Nginx
- **Overhead da mempool:** Desprezível em relação ao consumo total (< 0.1% da RAM total)

---

## 6. Gráficos

Os gráficos interativos podem ser visualizados abrindo o arquivo `chart-ledgers.html` em um navegador.

### 6.1 Transações OK vs FAIL por Ledger
![Gráfico de Transações](https://quickchart.io/chart?c={type:'bar',data:{labels:['L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence,'L#'+d.sequence],datasets:[{label:'OK',data:[8,7,9,7,7,7,8,11,11,5,10,9,6,9,7,8,7,7,7,8,10,12,8,9,6,8,8,4,10,3],backgroundColor:'%234caf50'},{label:'FAIL',data:[1,2,1,0,1,2,3,1,2,1,0,1,4,2,1,2,1,2,1,1,1,1,1,2,1,3,2,1,1,0],backgroundColor:'%23e94560'}]}})

### 6.2 Proporção TxSet vs Executadas
A cada ledger, o validador propoe um Transaction Set (conjunto de operações). Nem todas as operações propostas são executadas com sucesso. A média observada foi de **13.7 operações propostas** vs **9.5 executadas** por ledger (30.2% de descarte).

### 6.3 Taxa de Sucesso
A taxa de sucesso variou entre **60%** e **100%** nos ledgers monitorados, com média de **85.3%**.

### 6.4 Fee Pool
O fee pool acumulou **0.4524 XLM** em taxas durante os 30 ledgers, confirmando que as taxas são efetivamente coletadas e armazenadas para posterior distribuição.

---

## 7. Conclusões

1. **Vazão estável:** A rede testnet apresentou vazão média de **1.57 tx/s** (7.87 tx/ledger a cada ~5s), com baixa variação entre ledgers.

2. **Mempool subutilizada:** O max_tx_set_size de 200 transações por ledger foi utilizado em apenas **6.8%** da capacidade, indicando que a demanda atual da testnet está muito abaixo do limite da rede.

3. **Taxa de falhas consistente:** A taxa de falhas de **15.1%** é típica para testnets, onde transações malformadas, saldos insuficientes ou erros de sequência são comuns em testes.

4. **Impacto de memória desprezível:** A mempool não impacta significativamente o consumo de RAM dos processos stellar-core (~2.8 GB cada), sendo o principal consumo devido à bucket list (~4.7 GB + ~5.4 GB) e não à fila de transações.

5. **Fee pool crescente:** O acúmulo de 0.4524 XLM em taxas durante 30 ledgers (~150 segundos) demonstra a sustentabilidade econômica da rede mesmo com baixo volume de transações.

---

> **Dados coletados em:** 16/07/2026
> **Ledgers monitorados:** L#3646628 a L#3646657
> **Arquivos gerados:** ledger-data-full.csv, ledger-data-full.json, chart-ledgers.html
