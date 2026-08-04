# O Processo de Sincronização de um Nó Stellar

Quando um nó da rede Stellar é iniciado e precisa se atualizar com o estado atual da rede, ele entra em um processo conhecido como sincronização ou *catchup*. Esse processo não é um simples download de arquivos, mas sim uma reconstrução complexa e estruturada do estado do livro-razão (*ledger*).

Abaixo, detalhamos as etapas e os mecanismos técnicos que operam nos bastidores durante esse fluxo.

## 1. Arquitetura Básica: Core e Horizon

Durante a sincronização, geralmente há duas frentes de trabalho principais operando de forma complementar:

*   **Motor de Consenso (Stellar Core):** É a camada base, responsável por se comunicar com a rede, baixar o estado histórico, validar criptograficamente os dados e manter o registro oficial do *ledger*.
*   **Servidor de API (Horizon):** Atua como a ponte entre o nó e as aplicações clientes. Ele consome os dados validados pelo Core e os ingere em um banco de dados relacional, construindo índices que permitem consultas rápidas (como o histórico de transações de uma conta).

## 2. A Estrutura de Checkpoints

A rede Stellar não transfere o histórico baixando um *ledger* de cada vez. Para otimizar a propagação do estado, a rede agrupa os dados históricos em pacotes chamados de **checkpoints**. 

Cada checkpoint é criado a cada 64 ledgers. Ao invés de processar transação por transação de forma isolada, o nó foca em baixar e aplicar esses pacotes consolidados. O progresso da sincronização é medido pela quantidade de checkpoints que ainda precisam ser baixados e processados até que o nó alcance o alvo estabelecido pela rede.

## 3. O Que Significa "Aplicar" um Checkpoint?

A fase de aplicação é a mais intensiva do processo de sincronização. Ela transforma os arquivos compactados em um banco de dados utilizável e seguro. Esse fluxo é composto por quatro etapas fundamentais:

### A. Descompressão e Parse
O estado da rede é armazenado em arquivos chamados *History Archives*, que utilizam um formato binário compactado (`.xdr.gz`). O nó primeiro descompacta esses arquivos em memória e realiza o *parse* (tradução) da estrutura binária XDR (External Data Representation) para objetos compreensíveis pelo software.

### B. Mesclagem de Estado (Bucket Merge)
O armazenamento do estado na Stellar utiliza uma estrutura chamada HAS (*History Archive State*), baseada em "Buckets". Aplicar o checkpoint significa pegar o estado contido nos arquivos baixados e fundi-lo matematicamente com o estado local atual do nó. É um processo de substituição, criação e deleção de registros de contas, saldos e ofertas que reflete exatamente a fotografia da rede naquele momento.

### C. Validação Criptográfica
Uma característica fundamental de redes descentralizadas é a confiança baseada em matemática. O nó não confia cegamente no arquivo baixado. Após a mesclagem, o nó recalcula os hashes SHA-256 de toda a estrutura resultante. O hash raiz (*root hash*) calculado localmente deve ser idêntico ao hash aprovado pelo consenso da rede. Isso garante a integridade e confirma que os dados não foram adulterados.

### D. Ingestão no Banco de Dados
Enquanto o Core processa o estado, o serviço Horizon precisa disponibilizar esses dados para consultas. Isso exige que cada transação, efeito e operação contida nos checkpoints seja gravada em um banco de dados relacional (geralmente PostgreSQL). Durante essa etapa, milhares de linhas são inseridas e múltiplos índices são criados ou atualizados estruturalmente para viabilizar as buscas e retornos da API.

## 4. A Natureza do Esforço Computacional

O avanço, checkpoint por checkpoint, exige tempo por ser uma operação contínua de alto custo:

*   **Sequencialidade:** O processamento deve ocorrer estritamente em ordem. O nó precisa terminar de calcular, validar e aplicar as bases de um checkpoint antes de avançar para o próximo.
*   **Processamento de CPU:** O recálculo contínuo de árvores de hashes e validações criptográficas consome ciclos massivos de processador.
*   **Operações de I/O:** A tradução desses dados e a inserção massiva em banco de dados geram um volume altíssimo de leitura e escrita nos discos, exigindo bastante da camada de armazenamento.

Em resumo, a sincronização não é apenas copiar o estado; é um mecanismo de reprodução e auditoria projetado para que o nó reconstrua e ateste por si só a verdade absoluta da rede.