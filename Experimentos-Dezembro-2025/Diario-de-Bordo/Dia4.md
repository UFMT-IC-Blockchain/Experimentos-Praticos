# 📅 Diário de Bordo - Dia 04

**Foco:** Configuração Avançada de Rede Privada Stellar (Interconexão e Sincronização)

## ✅ Atividades Realizadas

### 1. Preparação do Nó Principal (gambyte2 - 192.168.207.212)
* **Automação de Peers:** Implementamos um script de entrypoint no `docker-compose.yml` para injetar automaticamente a configuração `KNOWN_PEERS`, garantindo que o nó saiba onde encontrar seus pares na inicialização.
* **Segurança e Rede:** Configuramos o Firewall (UFW) para liberar as portas essenciais:
  * `8000`: API Horizon (para consultas e transações).
  * `11625`: Protocolo P2P (para comunicação entre nós Stellar Core).
  * `11626`: HTTP Info (para diagnóstico do Core).
* **Solução para Arquivos de Histórico (History Archive):**
  * **Desafio:** O Stellar Quickstart em modo local não expõe os arquivos de histórico publicamente, o que impede outros nós de fazerem o "catchup" (sincronização inicial).
  * **Solução:** Configuramos o Nginx interno do container para servir a pasta de histórico (`/tmp/stellar-core/history/vs`) através da porta 8000. Isso permitiu que o nó secundário baixasse os blocos antigos via HTTP.

### 2. Configuração do Nó Secundário (gambyte1 - Local)
* **Resolução de Isolamento (Consenso):**
  * **Desafio:** O nó conectava ao peer, mas não sincronizava porque confiava apenas em si mesmo (`VALIDATORS=["$self"]`).
  * **Solução:** Atualizamos o `docker-compose.yml` para incluir o ID do nó principal (`GCTI6...`) na lista de validadores. Isso instruiu o nó local a aceitar os blocos validados pelo nó principal.
* **Configuração de Download de Histórico:**
  * **Desafio:** O nó travou no estado "Catching up" pois tentava copiar arquivos de histórico localmente (`cp`), mas eles estavam no outro computador.
  * **Solução:** Modificamos o `stellar-core.cfg` para usar o comando `curl`, apontando para o endpoint HTTP configurado no nó principal (`http://192.168.207.212:8000/archive/{0}`).
* **Resultado:** O nó completou o download dos buckets e transicionou para o estado **"Synced!"**.

### 3. Testes de Transação e Scripts
* Desenvolvemos scripts para facilitar o uso da rede:
  * `create-account-and-fund.sh`: Automatiza a criação de chaves e o financiamento via Friendbot.
  * `transaction_example.py`: Script Python robusto para realizar pagamentos.
* **Prova de Conceito:** Realizamos uma transferência de **50 XLM** entre duas contas (Alice e Bob) criadas na nossa rede privada, confirmando que o consenso e a propagação de transações estão funcionando perfeitamente.

## 📊 Status Atual da Rede

### Sincronização
* Ambos os nós estão **100% sincronizados**, compartilhando o mesmo ledger.
* O nó local (gambyte1) atua como um observador validador do nó principal (gambyte2).

### Serviços Disponíveis
* **Horizon API:** Acessível em ambas as máquinas. O nó local está finalizando a ingestão dos dados históricos para permitir consultas completas.
* **Friendbot:** Operacional no nó principal, permitindo criar contas de teste instantaneamente.

### Infraestrutura
* A rede agora suporta tanto sincronização em tempo real (via porta 11625) quanto recuperação de histórico (via porta 8000).

## 🚧 Próximos Passos

* **Validação Final:** Confirmar que o Horizon do nó local exibe corretamente o histórico de transações após o término da ingestão.
* **Resiliência:** Testar o comportamento da rede ao reiniciar os nós para garantir que as configurações (especialmente do Nginx e `stellar-core.cfg`) persistem corretamente.
* **Expansão:** Avaliar a adição de um terceiro nó para testar cenários de quórum mais complexos.
