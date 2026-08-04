# Experimentos — Julho 2026

Esta pasta contém os **experimentos de julho de 2026** realizados com um **nó Stellar Testnet (stellar-core + Horizon)** rodando em Docker. A versão em inglês está em `en/Experiments-July-2026/`.

Os experimentos focam na operação e análise de um nó completo da rede Stellar: sincronização inicial, monitoramento de ledgers/mempool, fluxo de transações, mudança de arquitetura (split do container em Core + Horizon) e otimização de armazenamento.

## Visão Geral

| Data / Pasta | Tema |
|---|---|
| [`2026-07-15/`](2026-07-15/) | Configuração inicial e sincronização do nó Stellar |
| [`2026-07-16/`](2026-07-16/) | Monitoramento de ledgers/mempool (30, 100 e 500 ledgers) + fluxo de transação |
| [`2026-07-17/`](2026-07-17/) | Análise de sincronização e catch-up do nó |
| [`2026-07-20/`](2026-07-20/) | Relatório completo de sincronização e estado do nó |
| [`2026-07-21/`](2026-07-21/) | Plano de implementação: split em containers Core + Horizon, análise SQL |
| [`2026-07-26/`](2026-07-26/) | Otimização de armazenamento no validador Stellar |
| [`Docker-Core-Horizon-Separado/`](Docker-Core-Horizon-Separado/) | Setup Docker: stellar-core e stellar-horizon em containers separados |
| [`Docker-MainNet/`](Docker-MainNet/) | Setup Docker: Core + Horizon na MainNet |
| [`Docker-MainNet-CoreOnly/`](Docker-MainNet-CoreOnly/) | Setup Docker: somente stellar-core na MainNet |
| [`Docker-Stellar/`](Docker-Stellar/) | Setup original de container único (stellar/quickstart) + diagramas Mermaid |

---

## `2026-07-15/` — Sincronização Inicial

- **`RELATORIO.md`** — Relatório completo da primeira execução da Stellar Testnet em Docker: arquitetura (container único com supervisord), sincronização inicial de ~14 min, bucket list (~10 GB de ~11 GB totais), consumo de RAM/armazenamento (~6 GB RAM).
- **`Relatorio-Dia.md`** — Resumo das atividades do dia, arquivos gerados e observações.
- **`RELATORIO-COMPLETO.pdf`** — Versão PDF do relatório completo (1,27 MB, 9 páginas), gerada via Puppeteer.

## `2026-07-16/` — Monitoramento e Transações

- **`Relatorio-Dia.md`** — Resumo das atividades de monitoramento do dia.
- **`Relatorio-Transacao-Submetida-Horizon-Local.md`** — Fluxo completo de uma transação submetida pela API Horizon local: da assinatura XDR até a inclusão no ledger, com evidências SQL/histórico.

### `Monitoramento-30-ledgers/` (30 ledgers, ~150 s)
- **`relatorio-mempool.md`** — Análise da mempool e vazão de transações: taxas de sucesso/falha, operações no TxSet vs. executadas, evolução do Fee Pool, consumo de memória.
- **`chart-ledgers.html`** — Gráficos interativos Chart.js dos dados do monitoramento (abrir no navegador).
- **`ledger-data.json` / `ledger-data.csv`** — Dados brutos do monitoramento (ledger a ledger).
- **`falhas-categorizadas.json`** — Falhas decodificadas/categorizadas por tipo.

### `Monitoramento-100-ledgers/` (100 ledgers)
- **`RELATORIO.md`** — Relatório do monitoramento.
- **`chart-ledgers-100.html`** — Gráficos interativos.
- **`dados-100-ledgers.json`** — Dados brutos.

### `Monitoramento-500-ledgers/` (500 ledgers, ~42 min)
- **`RELATORIO.md`** — Relatório do monitoramento.
- **`chart-ledgers-500.html`** — Gráficos interativos (rolagem horizontal, 158 KB).
- **`chart-ledgers-500-dividido.html`** — Mesmos gráficos divididos em 5 grupos.
- **`dados-500-ledgers.json`** — Dados brutos (309,7 KB).

## `2026-07-17/` — Sincronização e Catch-up

- **`analise-sincronizacao-stellar.md`** — Análise detalhada de como o nó sincroniza: descoberta, download do history archive, estado da bucket list, métricas de catch-up, papéis do SQLite vs PostgreSQL.
- **`Relatorio-Sincronizacao-Node-Up.md`** — Relatório do processo de catch-up do nó após subida.

## `2026-07-20/` — Relatório Completo de Sincronização

- **`Relatorio-Completo-Sincronizacao-Stellar.md`** — Relatório completo de sincronização e estado do nó: cabeçalhos de ledger, history archives, hashes de buckets, taxas de inserção durante o catch-up (até 194 inserts/s em `history_operation_participants`).

## `2026-07-21/` — Mudança de Arquitetura e Análise SQL

- **`00-PLANO-DE-IMPLEMENTACAO.md`** — Plano de implementação para dividir o container único `stellar/quickstart:testing` em dois containers independentes (stellar-core + stellar-horizon), com problemas do modelo atual, portas, volumes e arquitetura proposta.
- **`relatorio-duplo-container-catching-up.md`** — Relatório de teste do split (Core + Horizon em containers separados).
- **`relatorio-sincronizacao-de-no.md`** — O processo de sincronização de um nó Stellar (explicação genérica).
- **`Analise-SQL-Transactions-90s.md`** — Análise das transações SQL nos bancos da Stellar durante 90 segundos de monitoramento (padrão INSERT-heavy nas tabelas de histórico).

## `2026-07-26/` — Otimização de Armazenamento

- **`otimizacao-armazenamento-validator-stellar.md`** — Estudo de otimização de armazenamento no validador: SQLite (operacional) vs. buckets XDR (estado) vs. SQLite misc (rede), análise de WAL, níveis de merge, oportunidades de otimização.
- **`analyze_dbs.sh`** — Script shell para analisar os bancos de dados da Stellar.
- **`core_storage_analysis.sh`** — Script shell para análise completa de armazenamento do core validador.

## `Docker-Core-Horizon-Separado/` — Core + Horizon em Containers Separados

Resultado do plano de implementação de 2026-07-21: dois containers independentes em rede bridge.

- **`docker-compose.yml`** — Arquivo compose: `stellar-core` (portas 11625/11626) + `stellar-horizon` (porta 8000, PostgreSQL 5432) com healthchecks e volumes.
- **`README.md`** — Documentação do setup.
- **`stellar-core/`** — `Dockerfile`, `entrypoint.sh`, `stellar-core.cfg` (config do validador).
- **`stellar-horizon/`** — `Dockerfile`, `entrypoint.sh`, `horizon.env`, `nginx.conf`, `stellar-captive-core.cfg` (config do captive core).
- **`monitor_all_sql.sh`, `monitor_sqlite_core.sh`, `sqlite_core_mon.sh`, `sqlite_captive_mon.sh`, `sql_monitor.sql`** — Scripts de monitoramento (consultas SQL, estatísticas SQLite, WAL).
- **`core-full-log.txt`, `core-last-log.txt`, `horizon-full-log.txt`** — Logs de execução dos containers (evidência bruta).

## `Docker-MainNet/` — Core + Horizon na MainNet

Mesma arquitetura do setup acima, porém conectada à **MainNet Stellar** (rede `Public Global Stellar Network ; September 2015`), utilizada para estudos de armazenamento do modelo de bucket list.

- **`docker-compose.yml`** + **`README.md`** — Setup e documentação.
- **`stellar-core/`** e **`stellar-horizon/`** — Dockerfiles, entrypoints e configs para MainNet.

## `Docker-MainNet-CoreOnly/` — Somente Core na MainNet

Apenas stellar-core (sem Horizon), para estudar armazenamento e participação no consenso na MainNet com uso reduzido de recursos.

- **`docker-compose.yml`** + **`README.md`** — Setup e documentação.
- **`relatorio-armazenamento-mainnet.md`** — Relatório de armazenamento do nó Core na MainNet (bucket list, SQLite, impacto do Soroban, comparação MainNet vs TestNet).
- **`stellar-core/`** — Dockerfile, entrypoint e config para MainNet Core-only.

## `Docker-Stellar/` — Setup Original + Diagramas

- **`docker-compose.yml`** — Setup original de container único (`stellar/quickstart:testing`).
- **`diagramas/`** — Diagramas Mermaid da arquitetura:
  - `01-bancos.mmd` → Diagrama ER dos bancos (PostgreSQL Horizon + SQLite Core/Captive + bucket list)
  - `02-tabelas.mmd` → Mindmap das 33 tabelas PostgreSQL
  - `03-servicos.mmd` → Containers/serviços gerenciados pelo supervisord
  - `04-sincronizacao.mmd` → Fluxo de sincronização (descoberta, download de estado, catch-up)
  - `05-bucketlist.mmd` → Hierarquia da bucket list (11 níveis, merges)
  - `06-conexoes.mmd` → Conexões de rede entre os componentes
  - `png/` — Versões PNG compiladas de cada diagrama
  - `package.json` — Dependência Mermaid-CLI para compilar os diagramas
