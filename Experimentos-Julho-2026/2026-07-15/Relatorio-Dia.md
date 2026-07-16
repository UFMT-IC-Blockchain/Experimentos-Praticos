# Relatório de Atividades — 15/07/2026

**Disciplina:** Mestrado — Blockchain  
**Objetivo do Experimento:** Execução, monitoramento e análise de um container Docker completo da Stellar Testnet com Horizon, visando compreender a arquitetura de serviços, armazenamento, sincronização e conectividade da rede Stellar em ambiente controlado.

---

## 1. Atividades Realizadas

### 1.1 Verificação e Inspeção do Container em Execução

O container `stellar-testnet` (imagem `stellar/quickstart:testing`) encontrava-se em execução desde o dia anterior (14/07/2026). Foram realizadas as seguintes inspeções:

- **Identificação do container:** `docker ps` confirmou o container ativo com ID `4fbe5ce9b7cd`, IP interno `172.18.0.2`, volume persistente `stellar-data` montado em `/opt/stellar`.
- **Supervisord (PID 1):** Confirmou-se que o Supervisor gerenciava todos os processos filhos. Foram identificados os serviços gerenciados com suas respectivas prioridades e políticas de autostart.
- **Stellar Core Node (PID 291):** Nó de consenso ativo, consumindo aproximadamente 2,8 GB de RAM (~17,6% do container), conectado à rede testnet via porta P2P 11625. Sua configuração completa foi extraída do arquivo `/opt/stellar/core/etc/stellar-core.cfg`, revelando parâmetros como `CATCHUP_RECENT=100`, `UNSAFE_QUORUM=true`, `FAILURE_SAFETY=1`, e a lista de três validadores SDF (sdf_testnet_1, sdf_testnet_2, sdf_testnet_3).
- **Captive Core (PID 3985):** Subprocesso do Horizon responsável pela ingestão de dados, consumindo ~2,9 GB de RAM (~17,9%). Operando em modo `--console run --metadata-output-stream fd:3`, com portas P2P 11725 e HTTP 11726 (localhost). Um estudo comparativo detalhado entre Node e Captive Core foi documentado, destacando diferenças em participação no consenso, ciclo de vida, modo de execução e gerenciamento de bucket list.
- **Horizon API (PID 349):** Servidor REST consumindo ~182 MB de RAM, operando na porta interna 8001 e exposto via Nginx na porta 8000. Suas variáveis de ambiente foram integralmente capturadas, incluindo `DATABASE_URL`, `STELLAR_CORE_URL`, `ENABLE_CAPTIVE_CORE_INGESTION=true` e `INGEST=true`.
- **PostgreSQL (PID 330):** Banco de dados versão 14 (Alpine) com ~25 MB de RAM no processo principal, porta 5432, database `horizon` com 33 tabelas totalizando ~1,2 GB.
- **Nginx (PID 288/289):** Reverse proxy operando na porta 8000, encaminhando requisições ao Horizon na porta 8001.

### 1.2 Mapeamento da Estrutura de Diretórios

Foi realizada a exploração completa da árvore de diretórios do container em `/opt/stellar/`, documentando-se a hierarquia de diretórios de cada serviço:

- **Core:** Diretórios `bin/`, `etc/`, `buckets/` (bucket list), além dos bancos SQLite `stellar.db` (~18 MB) e `stellar-misc.db` (~22 MB).
- **Horizon:** Diretórios `bin/`, `etc/`, `captive-core/` contendo `stellar.db` (~21 MB), `stellar-misc.db` (~14 MB) e buckets isolados (~5,4 GB).
- **PostgreSQL:** Diretórios `data/` (~1,2 GB), `etc/` com `postgresql.conf`, `pg_hba.conf` e `pg_ident.conf`.
- **Nginx e Supervisor:** Diretórios de configuração em `nginx/etc/` e `supervisor/etc/`.

### 1.3 Captura de Conexões de Rede

Foram capturadas e documentadas todas as conexões de rede ativas do container:

- **Conexões P2P ESTABLISHED (porta 11625):** Nove peers identificados, incluindo IPs como `13.223.55.158`, `44.204.146.210`, `3.85.105.105`, entre outros.
- **Conexões SYN-SENT (em andamento):** Quatro tentativas de conexão a peers adicionais.
- **Conexão do Captive Core:** Um peer conectado na porta 11725 (`18.220.162.149`).
- **Validadores SDF:** Três validadores oficiais mapeados com nomes, chaves públicas e endereços (`core-testnet1/2/3.stellar.org`).
- **History Archives:** Três endpoints `history.stellar.org` utilizados para download de estado e buckets.

### 1.4 Análise dos Bancos de Dados

Realizou-se a análise detalhada de todos os bancos de dados envolvidos na arquitetura:

- **PostgreSQL (Horizon):** Database `horizon` com 33 tabelas, totalizando ~1,2 GB. As maiores tabelas identificadas foram `accounts` (497 MB), `accounts_signers` (428 MB), `trust_lines` (107 MB) e `accounts_data` (94 MB). Tabelas de histórico como `history_transactions` (10 MB) e `history_operations` (3,3 MB) também foram documentadas, além de tabelas auxiliares e de junção.
- **SQLite (Node Core):** `stellar.db` (~18 MB, com WAL ~62 MB) armazenando metadados do consenso; `stellar-misc.db` (~22 MB com WAL) para dados miscelâneos.
- **SQLite (Captive Core):** `captive-core/stellar.db` (~21 MB, com WAL ~33 MB); `captive-core/stellar-misc.db` (~14 MB com WAL).

### 1.5 Estudo da Bucket List

A bucket list — mecanismo de armazenamento de estado imutável e baseado em merge do Stellar Core — foi analisada em profundidade:

- **Estrutura:** 11 níveis hierárquicos (0 a 10), onde cada nível contém buckets representando snapshots do estado em diferentes escalas de tempo.
- **Tamanhos:** Desde ~25 KB (nível 0) até ~822 MB (nível 10), com merge periódico a cada 64 ledgers.
- **Diretórios:** Estrutura completa de `buckets/` documentada, incluindo subdiretórios `history/`, `meta-debug/`, `publishqueue/` e `tmp/`.
- **Bucket List (Node):** ~4,7 GB em `/opt/stellar/core/buckets/`.
- **Bucket List (Captive):** ~5,4 GB em `/opt/stellar/horizon/captive-core/captive-core/buckets/`.
- **Processo de Catchup:** Fluxo de 8 etapas documentado, desde a determinação do trigger ledger até a sincronização completa e participação no consenso SCP.

### 1.6 Documentação do Processo de Inicialização (Startup)

O script entrypoint `/start` (~600 linhas bash) foi analisado em suas 7 fases:

1. **process_args:** Definição de variáveis de rede (`NETWORK_PASSPHRASE`, `HISTORY_ARCHIVE_URLS`).
2. **copy_defaults:** Cópia de configurações padrão para diretórios de serviço.
3. **init_db:** Inicialização do PostgreSQL com criação de database e usuário.
4. **init_stellar_core:** Criação do schema SQLite e configuração do stellar-core.
5. **init_horizon:** Criação das 33 tabelas no PostgreSQL via `horizon db init`.
6. **exec_supervisor:** Inicialização do Supervisor com prioridades e políticas de autostart.
7. **Monitoramento:** Loops de verificação de status e inicialização sequencial dos serviços opcionais.

A timeline real de sincronização foi registrada, totalizando aproximadamente 14 minutos da inicialização do container até a ingestão completa do Horizon (ledger ~3.629.501).

### 1.7 Geração de Diagramas Mermaid

Foram elaborados seis diagramas no formato Mermaid para representar graficamente a arquitetura e os fluxos do sistema:

1. **Diagrama de Bancos (ER):** Mapeamento entidade-relacionamento entre PostgreSQL (Horizon), SQLite (Node e Captive Core) e Bucket Lists, com tamanhos e principais tabelas.
2. **Diagrama de Tabelas (Mindmap):** Organização das 33 tabelas do PostgreSQL em quatro categorias: Estado Atual, Histórico, Auxiliares e Tabelas de Junção.
3. **Diagrama de Serviços:** Arquitetura hierárquica dos serviços gerenciados pelo Supervisor, com detalhes de PIDs, consumo de memória, portas e relações de dependência.
4. **Diagrama de Sincronização (Sequência):** Fluxo completo de sincronização em 5 fases — Descoberta, Download de State, Checkpoints, Ingestão do Horizon e Operação Contínua.
5. **Hierarquia da Bucket List:** Representação dos 11 níveis com tamanhos, processo de merge e conexão com History Archives.
6. **Diagrama de Conexões de Rede:** Mapeamento de todas as conexões externas com validadores SDF, peers P2P, History Archives e usuário local.

Cada diagrama foi gerado em dois formatos: código-fonte Mermaid (`.mmd`) e imagem PNG compilada, armazenados em `Docker-Stellar/diagramas/`.

### 1.8 Elaboração dos Relatórios

Foram produzidos os seguintes documentos:

- **RELATORIO.md:** Documento principal unificado, contendo todas as seções — especificações da máquina, arquitetura geral, processo de inicialização, serviços do container, conexões de rede, bancos de dados, bucket list, fluxo de sincronização, diagramas e conclusão. Inclui tanto os códigos-fonte Mermaid quanto as imagens PNG compiladas.
- **RELATORIO-COMPLETO.pdf:** Versão em PDF do relatório, gerada via Puppeteer com formatação profissional para A4, incluindo cabeçalhos, rodapés com numeração de páginas e todos os diagramas renderizados.
- **Relatorio-Dia.md:** O presente documento, consolidando as atividades do dia em linguagem acadêmica.

### 1.9 Configuração do Repositório

- **.gitignore:** Adicionada e corrigida a exclusão do diretório `node_modules` em `Experimentos-Julho-2026/Docker-Stellar/diagramas/`.
- **Controle de versão:** Todos os arquivos foram versionados no repositório Git `UFMT-IC-Blockchain/Experimentos-Praticos` (branch `main`), com commits devidamente documentados.

---

## 2. Estrutura Final dos Arquivos Gerados

```
Experimentos-Julho-2026/
└── 2026-07-15/
    ├── RELATORIO.md                     # Relatório completo (1043 linhas)
    ├── RELATORIO-COMPLETO.pdf           # Versão PDF (1,27 MB, 9 páginas)
    └── Relatorio-Dia.md                 # Presente documento
└── Docker-Stellar/
    ├── docker-compose.yml               # Configuração Docker Compose
    └── diagramas/
        ├── 01-bancos.mmd                # Código Mermaid — Diagrama ER de Bancos
        ├── 02-tabelas.mmd               # Código Mermaid — Mindmap de Tabelas
        ├── 03-servicos.mmd              # Código Mermaid — Serviços do Container
        ├── 04-sincronizacao.mmd         # Código Mermaid — Fluxo de Sincronização
        ├── 05-bucketlist.mmd            # Código Mermaid — Hierarquia da Bucket List
        ├── 06-conexoes.mmd              # Código Mermaid — Conexões de Rede
        ├── package.json                 # Dependência do Mermaid-CLI
        ├── package-lock.json
        └── png/
            ├── 01-bancos.png            # Diagrama compilado (93 KB)
            ├── 02-tabelas.png           # Diagrama compilado (104 KB)
            ├── 03-servicos.png          # Diagrama compilado (63 KB)
            ├── 04-sincronizacao.png     # Diagrama compilado (149 KB)
            ├── 05-bucketlist.png        # Diagrama compilado (93 KB)
            └── 06-conexoes.png          # Diagrama compilado (106 KB)
```

---

## 3. Observações e Resultados

- O container `stellar/quickstart:testing` consome aproximadamente **6 GB de RAM** e **~10-11 GB de armazenamento** em volume Docker, demonstrando a complexidade operacional de um nó completo da Stellar Testnet.
- A arquitetura de duas instâncias do Stellar Core (Node + Captive) mostrou-se eficaz para separar as responsabilidades de consenso e ingestão de dados, permitindo que o Horizon opere sem interferir no nó principal.
- O tempo de sincronização inicial de ~14 minutos evidencia a otimização proporcionada pelo uso de History Archives e buckets pré-computados.
- A bucket list, com seus 11 níveis hierárquicos e processo de merge periódico, constitui o principal gargalo de armazenamento, representando ~10 GB dos ~11 GB totais.

---

> **Relatório gerado em:** 15/07/2026  
> **Container:** stellar/quickstart:testing (testnet)  
> **Ledger no momento da coleta:** ~3,629,501
