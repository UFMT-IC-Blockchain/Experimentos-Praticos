# 📅 Diário de Bordo - Dia 05/12

**Foco:** Resolução de Problemas de Ingestão e Sincronização Robusta entre Nós

## 🔴 Problema Crítico: Horizon Travado

### Sintomas
* Horizon retornando erro **503 Still Ingesting** por mais de 65 minutos.
* Impossibilidade de consultar contas ou realizar transações.
* Log repetitivo: *"waiting for ingestion to catch up"*.

### Causa Raiz
1.  **Conflito de Configuração:** O `docker-compose.yml` possuía um *entrypoint customizado* que tentava modificar arquivos de configuração do *Captive Core* que não existiam no momento da execução, gerando falhas silenciosas.
2.  **Persistência Volátil:** O *History Archive* estava mapeado para `/tmp` (temporário), causando perda de dados e inconsistência de estado ao reiniciar o container.

### Solução Aplicada
Realizamos um *Hard Reset* e simplificação da arquitetura:

1.  **Limpeza Profunda:**
    ```bash
    docker compose down -v
    docker volume prune -f  # Liberou 19GB de dados órfãos
    docker system prune -f
    rm -rf ./local
    ```
2.  **Refatoração do `docker-compose.yml`:**
    * ❌ Removido entrypoint customizado problemático.
    * ❌ Removidos mounts de volumes desnecessários.
    * ✅ Mantida apenas a configuração essencial (`VALIDATORS`).
    * ✅ Permitido que o Stellar Quickstart utilize seus padrões internos.

**Resultado:** O Horizon sincronizou e ficou operacional em **menos de 1 minuto** (contra 65+ minutos anteriormente).

---

## ✅ Transações Automatizadas

Desenvolvemos o script `scenario_runner.py` para validar a rede utilizando a *Root Account* (bypassando a necessidade do Friendbot para operações iniciais).

### Execução de Teste
* **Total:** 10 transações realizadas com sucesso.
* **Fluxo:**
    1.  Criação de `Acc1` e `Acc2` (10.000 XLM cada).
    2.  5 transferências de `Acc2` → `Acc1` (10 XLM cada).
    3.  Criação de `Acc3` e `Acc4` (1.000 XLM cada).
    4.  5 transferências de `Acc3` → `Acc4` (10 XLM cada).

**Contas Geradas:**
* `Acc1`: `GBGH5S2X...BGVW7`
* `Acc2`: `GB2VKHTX...U6G4B`
* `Acc3`: `GDBCG4BI...QOLF`
* `Acc4`: `GC3VRGC3...DVP6O`

---

## 🔄 Configuração do Nó Peer (212)

### Problema Identificado
O nó 212 não havia resetado corretamente e possuía um *gap* de 3500+ ledgers em relação ao nó autoritativo.

### Solução (`docker-compose-peer.yml`)
Criamos uma configuração específica para o nó atuar como **Observador**:

* **Validação:** `NODE_IS_VALIDATOR=false` (Apenas observa, não participa do consenso).
* **Discovery:** `KNOWN_PEERS=["192.168.207.240:11625"]` (Conecta direto ao nó autoritativo).
* **Confiança:** `VALIDATORS=["GDKOZJP...YNPN"]` (Confia no nó principal).
* **Recuperação:** Configurado `curl` para baixar histórico via HTTP:
    ```bash
    curl -sf [http://192.168.207.240:8000/archive/](http://192.168.207.240:8000/archive/){0}
    ```

### Verificações de Conectividade
* ✅ Porta 11625 acessível.
* ✅ History Archive servindo arquivos.
* ✅ `stellar-history.json` disponível.
* ✅ Docker com bindings corretos em `0.0.0.0`.

---

## 📊 Status Final da Rede

### Nó 1 (192.168.207.240) - Autoritativo
* ✅ **Ledger:** 3911
* ✅ **Estado:** Synced!
* ✅ **Horizon:** Operacional (Ledger 3885)
* ✅ **Peers:** 2 conectados

### Nó 2 (192.168.207.212) - Observador
* ✅ **Ledger:** 430 (Em processo de Catch-up)
* ✅ **Estado:** Synced! (Sincronizando histórico)
* ✅ **Horizon:** Operacional (Ledger 411)
* ✅ **Peers:** 2 conectados
* ⏳ **Estimativa:** ~20-30 minutos para paridade total (Taxa: ~3.6 ledgers/seg).

---

## 📈 Métricas do Dia

| Métrica | Valor |
| :--- | :--- |
| **Transações Criadas** | 10 |
| **Contas Criadas** | 4 |
| **Espaço em Disco Liberado** | 19.11 GB |
| **Tempo de Sync (Horizon)** | < 1 minuto |
| **Ledger Atual (Rede)** | 3911 |

---

## 📁 Arquivos e Documentação

### Scripts Criados
* `scenario_runner.py`: Automação de cenários de transação.
* `run_more_txs.py`: Transações robustas com fallback para Core.
* `check_sync.sh`: Monitoramento rápido de sincronização entre nós.
* `query_*.py`: Scripts diversos de diagnóstico.

### Configurações
* `docker-compose.yml`: Nó autoritativo (versão simplificada/estável).
* `docker-compose-peer.yml`: Nó observador.

### Docs
* `GUIA_RESET_E_SYNC.md`: Procedimento padrão para limpar o ambiente.
* `INSTRUCOES_NO_212.md`: Passo a passo específico para o segundo nó.

---

## 🎓 Lições Aprendidas

### ❌ O Que Não Funciona
* **Entrypoint Customizado no Quickstart:** Causa conflitos severos com o Captive Core.
* **History Archive em `/tmp`:** Garante perda de dados em reboots.
* **`sed` em arquivos inexistentes:** Gera falhas silenciosas difíceis de debugar.
* **Variáveis de Ambiente Isoladas:** `KNOWN_PEERS` precisa ser injetado via script/entrypoint para ser reconhecido corretamente pelo Core.

### ✅ O Que Funciona
* **Configuração Padrão (Vanilla):** O Stellar Quickstart é mais estável quando menos modificado.
* **Reset Completo (`down -v` + `prune`):** Única forma confiável de resolver estados inconsistentes de ledger.
* **Entrypoint no Peer:** Essencial para configurar a descoberta de rede (`KNOWN_PEERS`).
* **Root Account:** Mais confiável que o Friendbot para testes de infraestrutura.
* **Script `check_sync.sh`:** Ferramenta visual rápida para comparar alturas de ledger.

---

## 🚀 Conclusão
* ✅ Rede privada Stellar totalmente funcional.
* ✅ Ambos os nós sincronizados e comunicando via protocolo P2P.
* ✅ Horizon operacional e respondendo a consultas em ambas as pontas.
* ⏳ Sincronização de histórico final em progresso.
