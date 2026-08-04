# Relatório de Sincronização: Análise do Processo de Catch-up do Nó Stellar

**Data:** 2026-07-18
**Rede:** Stellar Testnet ("Test SDF Network ; September 2015")
**Container:** stellar-testnet (stellar/quickstart:testing)
**Versão Core:** v27.1.0
**Estado Final:** Synced! (Ledger 3.663.823)

---

## 1. Introdução

Este relatório documenta o processo de **sincronização inicial (catch-up)** de um nó Stellar Core ao se conectar à Testnet. O objetivo é elucidar os mecanismos internos de recuperação de estado, explicar a relação entre buckets e checkpoints, e justificar a duração observada do processo.

---

## 2. Arquitetura de Armazenamento

O Stellar Core organiza os dados históricos da rede em duas estruturas complementares: **buckets** (snapshots de estado) e **checkpoints** (logs de transações).

### 2.1 Buckets (Snapshots)

Buckets são arquivos binários no formato XDR que contêm o **estado completo** da rede em um determinado ponto no tempo. Eles armazenam contas, trustlines, offers, dados de contratos Soroban, etc. — todo o estado necessário para reconstruir a ledger sem reprocessar transações históricas.

```
Tamanho dos 5 maiores buckets baixados pelo nó:

bucket-ff26b4f5...7efd.xdr   785 MB   │████████████████████████████████████████
bucket-eb7625ce...4b72.xdr   610 MB   │███████████████████████████████
bucket-d8522ede...2d730.xdr   600 MB   │██████████████████████████████
bucket-8a27deda...b125.xdr   452 MB   │█████████████████████████
bucket-b2a2c09a...d09b.xdr   355 MB   │███████████████████
                                    ──┴────────────────────
                                    Total buckets: 4,4 GB
```

Os buckets são organizados em **níveis de merge** (0 a 6). Buckets de nível baixo são pequenos e frequentes; buckets de nível alto (snap) são grandes e representam o estado consolidado.

```
Níveis de Merge dos Buckets:

Level 0 (base):  ~677 buckets    ██▌ (pequenos, dados recentes)
Level 1:         ~2.797 buckets  ███████████▌
Level 2:         ~758 buckets    ███▌
Level 3:         ~208 buckets    █▌
Level 4:         ~63 buckets     ▎
Level 5:         ~18 buckets     ▏
Level 6 (snap):  ~4 buckets      ▏ (785 MB o maior)
```

### 2.2 Checkpoints (Logs de Transações)

Checkpoints são arquivos que contêm as **transações brutas** de 64 ledgers consecutivos (~5 minutos de atividade da rede). Diferentemente dos buckets, checkpoints não contêm o estado final — apenas as operações que modificam o estado.

```
Estrutura de um checkpoint:

 Ledger 1 ─┬─ Transação A (pagamento)
           ├─ Transação B (create_account)
           ├─ Transação C (set_options)
           └─ Transação D (soroban_invoke)
 
 Ledger 2 ─┬─ Transação E (manage_offer)
           ├─ ...
           ...
 
 ... até 64 ledgers (~620 transações por checkpoint)
```

## 3. O Mecanismo CATCHUP_RECENT

### 3.1 Definição

A diretiva `CATCHUP_RECENT=100` no arquivo `stellar-core.cfg` determina a **estratégia de recuperação** do nó:

> "Baixe um bucket snapshot que cubra pelo menos N ledgers atrás, depois faça replay dos checkpoints restantes."

### 3.2 Funcionamento

```
Processo de seleção do snapshot:

Linha do tempo da rede:

Genesis  ─────┬──────┬──────┬──────┬──────┬──────┬──────► Agora (ledger 3.663.823)
              │      │      │      │      │      │
        Buckets disponíveis nos archives da SDF:
              │      │      │      │      │      │
              ▼      ▼      ▼      ▼      ▼      ▼
              B1     B2     B3     B4     B5     B6
                                              ▲
                                              │
                                    Bucket snapshot escolhido
                                    (mais recente que cobre
                                     ≥ 100 ledgers atrás)
```

O Stellar Core busca no archive histórico o **bucket snapshot mais recente disponível** que corresponda a um checkpoint a pelo menos `CATCHUP_RECENT` ledgers de distância do ledger alvo. No caso concreto:

```
Bucket snapshot escolhido:
  Data de criação: 16/07/2026 ~01:00 UTC
  Ledger aproximado: 3.647.615

Ledger alvo (início): 3.663.423
Diferença: 15.808 ledgers = 247 checkpoints (de 64 em 64)
```

O valor `100` em `CATCHUP_RECENT=100` não significa "100 checkpoints" — significa "pelo menos 100 ledgers de margem". Como os snapshots são esparsos, a margem real foi de **15.808 ledgers**.

### 3.3 Trade-off

```
CATCHUP_RECENT alto (ex: 1000000):
  ├─ Baixa bucket MAIS RECENTE     (menos dados, download rápido)
  └─ MAIS checkpoints para replay   (mais tempo de CPU/SQLite)

CATCHUP_RECENT baixo (ex: 100):
  ├─ Baixa bucket MAIS ANTIGO      (mais dados, download lento)
  └─ MENOS checkpoints para replay  (menos tempo de CPU/SQLite)
```

| Estratégia | Download | Replay | Tempo Total |
|:-----------|:---------|:-------|:------------|
| Snapshot recente + replay longo | Rápido (1 bucket) | Lento (247 checkpoints) | **Horas** |
| Snapshot antigo + replay curto | Lento (muitos buckets) | Rápido (poucos checkpoints) | **Variável** |
| Sem CATCHUP_RECENT (full replay) | Nenhum | Muito lento (3,6M ledgers) | **Dias** |

## 4. Ciclo de Sincronização Observado

### 4.1 Timeline

```
00:22:42  ─── Início do container (stellar-core node)
                │
                ▼
       ┌─────────────────────┐
       │  Download de        │
       │  buckets (4,4 GB)   │ ←──── Apenas ~30 segundos
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │  Apply buckets      │
       │  (verificação SHA)  │ ←──── Estado reconstruído até ledger ~3.647.615
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │  Download & apply   │
       │  checkpoints        │ ←─────── 247 checkpoints para reprocessar
       │  (247 = 15.808 led.)│
       └─────────┬───────────┘
                 │
          ┌──────┴──────┐
          ▼              ▼
    ┌──────────┐  ┌──────────┐
    │ 38% done │  │ 65% done │
    │ (151/247)│  │ (86/247) │
    └──────────┘  └──────────┘
          │              │
          ▼              ▼
    ┌──────────┐  ┌──────────┐  ←──── A rede continua produzindo
    │ 89% done │  │ 88% done │       novos ledgers (1 a cada 5s)
    │ (24/247) │  │ (26/247) │       enquanto o replay roda
    └──────────┘  └──────────┘
          │              │
          ▼              ▼
    ~20:40h  ──── Synced! (ledger 3.663.823)
```

### 4.2 Oscilação da Porcentagem

Durante o catch-up, observou-se que a porcentagem de progresso **oscilava** mesmo com checkpoints sendo processados:

```
Log exemplo:         Checkpoints left   % done
                     151                (39%)
                     150                (39%)   ← mesma %!
                     149                (39%)   ← mesma %!
                     148                (40%)   ↑ subiu só 1%
```

**Explicação:** A porcentagem é calculada como:

```
% = (total_restantes - total_inicial) / total_atual
```

Onde `total_atual` cresce continuamente porque a rede produz ~1 ledger a cada 5 segundos. Enquanto o nó processa checkpoints antigos, **novos checkpoints são adicionados ao denominador** — o progresso "corre atrás de um alvo móvel".

```
Visualização do alvo móvel:

  Ledger atual da rede ─────►████████████████████████████████████████████████
                                      ↑
                                     Alvo móvel (sobe ~1 ledger/5s)
  
  Ledger do nó ──────────►███████████
                                ↑
                        Nó processando checkpoints
  
  Gap: quanto menor o gap, maior a %
  Como o alvo sobe, a % pode estagnar mesmo com o nó avançando
```

### 4.3 Posição Relativa Node vs Horizon

O container mantém **dois processos stellar-core** independentes, cada um baixando seus próprios buckets e checkpoints:

```
Node (porta 11626)       ──► ledger 3.663.423 (catch-up)
   │
   │ Gap de ~2.100 ledgers
   │ (iniciou 3,5 min antes)
   ▼
Horizon Captive Core     ──► ledger 3.663.487 (catch-up)
(porta 11726)
   │
   │ Gap de ~6 ledgers
   │ (latência de processamento)
   ▼
Horizon (ingest)         ──► ledger 3.663.481 (ingestão no PostgreSQL)
```

## 5. Análise de Performance do Replay

### 5.1 Por que o replay é lento?

Cada checkpoint de 64 ledgers exige:

1. **Download** do arquivo XDR do history archive (~ rede)
2. **Desserialização** do XDR para estruturas em memória
3. **Reaplicação** de ~620 transações no SQLite (escritas sequenciais)
4. **Execução de contratos Soroban** (CPU intensivo — 261 bilhões de instruções)
5. **Verificação de hashes SHA256** de cada operação
6. **Merge de buckets** nos níveis inferiores

### 5.2 Perfil de Carga (métricas do core node)

| Métrica | Valor |
|:--------|:------|
| Ledgers aplicados com sucesso | 39.129 |
| Ledgers com falha | 7.742 |
| Transações aplicadas | 46.871 |
| Operações aplicadas | 71.502 |
| Média de transações/ledger | ~9,7 |
| Média de operações/ledger | ~15,0 |
| Chamadas Soroban (host functions) | 31.194 |
| Instruções de CPU (Soroban) | ~261 bilhões |

### 5.3 Distribuição do Estado nos Buckets

O estado da Testnet é dominado por contratos inteligentes Soroban, o que torna o replay mais custoso:

```
Composição do estado (1,84 GB descompactado):

PERSISTENT_CONTRACT_DATA  40,2%  ██████████████████████████████████████
ACCOUNT                   20,3%  ██████████████████▌
CONTRACT_CODE             17,7%  █████████████████
TTL                       11,8%  ██████████▌
TRUSTLINE                  2,5%  ██▌
DATA                       2,7%  ██▌
OFFER                      0,5%  ▌
OUTROS (8 categorias)      4,3%  ███▌
                                      ──┴────
                                      Total: 100%
```

**Observação:** Contratos Soroban (PERSISTENT_CONTRACT_DATA + CONTRACT_CODE + TTL) somam ~70% do estado. Cada transação Soroban exige compilação WASM, execução de host functions e verificação de metadados — significativamente mais caro que uma transação simples de pagamento.

### 5.4 Estado do SQLite Durante o Catch-up

```
Arquivo                    Tamanho    Função
stellar.db                 21 MB      Banco principal (ledgers)
stellar.db-wal             44 MB      Write-Ahead Log (escritas intensas)
stellar.db-shm             96 KB      Shared Memory
stellar-misc.db            208 KB     Metadados diversos
stellar-misc.db-wal        40 MB      WAL dos metadados
```

O WAL (Write-Ahead Log) de 44 MB indica **escrita intensa e contínua** — o SQLite está sob carga constante durante o replay dos checkpoints.

## 6. Armazenamento Total

```
Armazenamento total em /opt/stellar/: ~15 GB

core/          4,6 GB  │███████████████████████████████▌
  ├── buckets/ 4,4 GB │██████████████████████████████
  └── stellar  21 MB  │▏

horizon/       4,7 GB  │████████████████████████████████
  ├── captive- 4,6 GB │██████████████████████████████▌
  └── stellar  21 MB  │▏

postgresql/    5,3 GB  │████████████████████████████████████▎
  ├── accounts 873 MB │██████
  ├── signers  1,4 GB │██████████▏
  ├── txs      679 MB │█████
  └── outras   2,3 GB │███████████████▋

lab/           171 MB  │█▎
outros         116 KB  │▏
```

**Duplicação de buckets:** O Core Node e o Captive Core do Horizon mantêm buckets independentes (~4,4 GB cada = ~8,8 GB duplicados). Isso é intencional — o Horizon usa captive core para isolar a ingestão do consenso.

## 7. Conclusões

1. **O gargalo não é download, é replay.** Os buckets (4,4 GB) foram baixados em segundos; os 247 checkpoints (~15.808 ledgers) levaram horas para reprocessar no SQLite.

2. **CATCHUP_RECENT=100 não significa "100 checkpoints".** O valor define uma margem mínima em ledgers. Devido à esparsidade dos snapshots nos archives, a margem real foi de ~15.808 ledgers.

3. **A porcentagem oscila porque o alvo é móvel.** Novos ledgers são produzidos pela rede durante o catch-up, fazendo o denominador do cálculo de progresso crescer continuamente.

4. **Soroban torna o replay mais lento.** Contratos inteligentes representam ~70% do estado da Testnet, e cada transação Soroban exige compilação WASM + execução de host functions, aumentando o custo de CPU por checkpoint.

5. **A duplicação de buckets entre Core Node e Captive Core (~8,8 GB) é o preço do isolamento** entre o processo de consenso e o processo de ingestão de dados do Horizon.

---

## Referências

- Stellar Core Documentation: https://developers.stellar.org/docs/data/history
- Stellar Bucket System: https://github.com/stellar/stellar-core/blob/master/docs/software/ledger.md
- Configuração do nó analisado: `/opt/stellar/core/etc/stellar-core.cfg`
- Logs de sincronização: `/var/log/stellar-core/`
- Dados brutos coletados em 2026-07-18 via `curl http://localhost:11626/info` e `curl http://localhost:11626/metrics`
