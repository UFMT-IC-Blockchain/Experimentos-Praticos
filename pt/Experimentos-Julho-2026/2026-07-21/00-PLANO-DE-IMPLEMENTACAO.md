# Plano de Implementação: Split do Container Stellar em Core + Horizon Separados

**Data:** 2026-07-21
**Base:** Setup atual `stellar/quickstart:testing` (single container)
**Destino:** Dois containers independentes: `stellar-core` (validador) + `stellar-horizon` (API)

---

## 1. Resumo da Arquitetura Atual

```
SINGLE CONTAINER (stellar/quickstart:testing)
supervisord gerencia 5+ processos no mesmo container:

┌─────────────────────────────────────────────────────┐
│                    CONTAINER ÚNICO                   │
│                                                      │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────┐ │
│  │ Core Node    │   │ Captive Core │   │ Horizon  │ │
│  │ (validador)  │   │ (filho do    │   │ (API)    │ │
│  │ P2P + HTTP   │   │  Horizon)    │   │          │ │
│  │ SQLite+buckts│   │ SQLite+buckts│   │ PostgreSQL│ │
│  └──────┬───────┘   └──────┬───────┘   └────┬─────┘ │
│         │                  │                │        │
│   11625/11626         11725/11726         8001      │
│         │                  │                │        │
│         └──────────────────┴────────────────┘        │
│                    nginx (porta 8000)                 │
└─────────────────────────────────────────────────────┘
```

### Problemas do modelo atual:
1. **Um container gerencia tudo** — se o Core trava, o Horizon também é afetado
2. **Recursos compartilhados** — CPU/RAM sem isolamento entre processos
3. **Buckets duplicados** — Core Node + Captive Core baixam ~8,5 GB dos mesmos dados
4. **Logs misturados** — Todos os serviços logam no mesmo stdout
5. **Reinicialização conjunta** — Não é possível atualizar Core sem reiniciar Horizon

---

## 2. Arquitetura Proposta

```
DOIS CONTAINERS INDEPENDENTES

┌──────────────────────────────┐      ┌──────────────────────────────────┐
│   CONTAINER 1: stellar-core  │      │   CONTAINER 2: stellar-horizon   │
│   (Validador / Consensus)    │      │   (API / Ingestion)              │
│                              │      │                                  │
│  ┌────────────────────────┐  │      │  ┌────────────────────────────┐  │
│  │   stellar-core         │  │      │  │   PostgreSQL (14)          │  │
│  │                        │  │      │  │   - banco: horizon        │  │
│  │   - Consenso SCP       │  │      │  │   - porta 5432            │  │
│  │   - Rede P2P           │  │      │  └────────────────────────────┘  │
│  │   - SQLite (ledgers)   │  │      │             │                    │
│  │   - Buckets (4,3 GB)   │  │      │  ┌────────────────────────────┐  │
│  │                        │  │      │  │   stellar-horizon          │  │
│  │   Portas:              │  │      │  │                            │  │
│  │   11625 (P2P)          │  │      │  │   - API REST na porta 8001│  │
│  │   11626 (HTTP admin)   │  │      │  │   - Captive Core (interno) │  │
│  └────────────────────────┘  │      │  │   - Pipe fd:3 do captive  │  │
│                              │      │  │   - PostgreSQL             │  │
│  Volumes:                    │      │  │                            │  │
│   - stellar-core-data:/opt   │      │  │   Portas:                  │  │
│                              │      │  │   8000 (nginx) → 8001     │  │
│                              │      │  │   11725 (captive P2P)     │  │
│                              │      │  │   11726 (captive HTTP)    │  │
│                              │      │  └────────────────────────────┘  │
│                              │      │                                  │
│                              │      │  Volumes:                        │
│                              │      │   - horizon-data:/opt/stellar   │
│                              │      │   - pgdata:/var/lib/postgresql  │
└──────────────────────────────┘      └──────────────────────────────────┘
         │                                       │
         │ (sem dependência direta)              │
         │                                       │
         ▼                                       ▼
   P2P: sdf_testnet{1,2,3}              P2P: sdf_testnet{1,2,3}
   Archive: history.stellar.org         Archive: history.stellar.org
```

### Fluxo de Dados

```
Container 1 (Core):
  P2P (11625) → SCP Consensus com validadores SDF
  HTTP (11626) → Admin info, métricas, upgrades
  Buckets (4,3 GB) → Estado do ledger
  SQLite (21 MB) → Metadados locais
  → NÃO envia dados para o Horizon

Container 2 (Horizon):
  Captive Core (interno, porta 11726) → P2P com validadores SDF
  Captive Core → Pipe (fd:3) → Horizon (metadados do ledger)
  Horizon → PostgreSQL (dados processados)
  nginx (8000) → proxy para Horizon (8001)
  → NÃO depende do Container 1 para ingestão
```

---

## 3. Análise de Dependências

### 3.1 O Horizon PRECISA do Core Node?

**Não para ingestão.** O Horizon com `ENABLE_CAPTIVE_CORE_INGESTION=true`:
- Gerencia seu próprio processo stellar-core (captive core)
- O captive core se conecta diretamente à rede P2P da Stellar
- O captive core baixa buckets próprios dos history archives
- O Horizon lê metadados via pipe do captive core → NÃO usa HTTP do core node

**STELLAR_CORE_URL** (usado apenas para `transaction submission` quando `INGEST=false`) → não se aplica aqui.

**Conclusão:** Os dois containers são **independentes** - podem rodar sem se comunicar.

### 3.2 Vantagens do Split

| Aspecto | Single Container | Containers Separados |
|:--------|:----------------|:--------------------|
| **Isolamento de falhas** | Core travado → tudo fora | Core travado → Horizon ainda serve API |
| **Recursos** | CPU/RAM compartilhados | Limits independentes por container |
| **Atualização** | Precisa rebuildar a imagem inteira | Pode atualizar Core ou Horizon separadamente |
| **Logs** | Misturados no stdout | Logs separados por container |
| **Armazenamento** | ~8,5 GB duplicados | ~8,5 GB duplicados (mesmo) |
| **Complexidade** | Simples (1 container) | Mais complexo (orquestração) |

### 3.3 Desvantagens do Split

| Aspecto | Impacto |
|:--------|:--------|
| **Buckets duplicados** | Continua igual (~8,5 GB total) |
| **Configuração extra** | Precisa configurar rede, volumes, healthchecks |
| **Sincronização inicial** | Ambos precisam fazer catch-up independentemente |
| **Manutenção** | Duas imagens Docker para gerenciar |

---

## 4. Estrutura de Diretórios Proposta

```
Docker-Core-Horizon-Separado/
│
├── 00-PLANO-DE-IMPLEMENTACAO.md     ← este arquivo
│
├── stellar-core/                    ← Container do Core Node (validador)
│   ├── Dockerfile                   ← Imagem docker do Core
│   ├── stellar-core.cfg             ← Configuração do Core
│   ├── entrypoint.sh                ← Script de inicialização
│   └── .dockerignore
│
├── stellar-horizon/                 ← Container do Horizon (API + ingestão)
│   ├── Dockerfile                   ← Imagem docker do Horizon
│   ├── stellar-captive-core.cfg     ← Configuração do captive core
│   ├── horizon.env                  ← Variáveis de ambiente do Horizon
│   ├── entrypoint.sh                ← Script de inicialização
│   ├── nginx.conf                   ← Configuração do nginx
│   └── .dockerignore
│
├── docker-compose.yml               ← Orquestração dos dois containers
├── .env                             ← Variáveis comuns (network, passphrase)
└── README.md                        ← Instruções de uso
```

---

## 5. Configuração de Rede entre Containers

```
Rede Docker: stellar-network (bridge)

Container: stellar-core
  networks:
    stellar-network:
      ipv4_address: 172.20.0.10
  ports:
    - "11625:11625/tcp"   # P2P (exposto ao host)
    - "11626:11626/tcp"   # HTTP admin

Container: stellar-horizon
  networks:
    stellar-network:
      ipv4_address: 172.20.0.11
  ports:
    - "8000:8000/tcp"     # HTTP público (nginx → Horizon)
    - "5432:5432/tcp"     # PostgreSQL (opcional, debug)
  
  # Captive core usa portas internas (não expostas): 11725 (P2P), 11726 (HTTP)
```

### Portas Expostas vs Internas

| Serviço | Container | Porta Interna | Exposta? | Uso |
|:--------|:----------|:--------------|:---------|:----|
| Core P2P | stellar-core | 11625 | Sim | Consenso com validadores |
| Core HTTP | stellar-core | 11626 | Sim | Admin/métricas |
| Captive P2P | stellar-horizon | 11725 | **Não** | Apenas interno |
| Captive HTTP | stellar-horizon | 11726 | **Não** | Apenas interno (loopback) |
| Horizon API | stellar-horizon | 8001 | Não (nginx) | API REST |
| nginx público | stellar-horizon | 8000 | Sim | Proxy para Horizon |
| PostgreSQL | stellar-horizon | 5432 | Opcional | Banco do Horizon |

---

## 6. Volumes e Dados Persistentes

### Container 1: stellar-core

```yaml
volumes:
  - core-data:/opt/stellar/core    # SQLite + buckets + config
```

### Container 2: stellar-horizon

```yaml
volumes:
  - horizon-data:/opt/stellar/horizon    # Captive core data + config
  - pgdata:/var/lib/postgresql/14/main   # PostgreSQL data
```

### Tamanho estimado dos volumes

| Volume | Tamanho Estimado | Conteúdo |
|:-------|:-----------------|:---------|
| core-data | ~4,6 GB | SQLite (21 MB) + WAL (44 MB) + Buckets (4,3 GB) + índices |
| horizon-data | ~4,7 GB | SQLite captive (21 MB) + Buckets (4,3 GB) + configs |
| pgdata | ~5,3 GB | 33 tabelas, ~9,3M linhas, WAL |
| **Total** | **~14,6 GB** | |

---

## 7. Dockerfiles

### 7.1 stellar-core/Dockerfile

```dockerfile
# Imagem baseada na stellar/quickstart:testing, extraindo apenas o Core
FROM stellar/quickstart:testing AS base

# Estágio 1: Apenas stellar-core
FROM ubuntu:22.04

# Instalar stellar-core (copiado da imagem oficial ou instalado via apt)
COPY --from=base /usr/bin/stellar-core /usr/bin/stellar-core
COPY --from=base /usr/lib/x86_64-linux-gnu/lib* /usr/lib/x86_64-linux-gnu/

# Configuração
COPY stellar-core.cfg /opt/stellar/core/etc/stellar-core.cfg
COPY entrypoint.sh /entrypoint.sh

RUN useradd -m -s /bin/bash stellar && \
    mkdir -p /opt/stellar/core /var/log/stellar-core && \
    chown -R stellar:stellar /opt/stellar/core /var/log/stellar-core && \
    chmod +x /entrypoint.sh

VOLUME ["/opt/stellar/core", "/var/log/stellar-core"]
EXPOSE 11625 11626

USER stellar
ENTRYPOINT ["/entrypoint.sh"]
CMD ["stellar-core", "--conf", "/opt/stellar/core/etc/stellar-core.cfg"]
```

### 7.2 stellar-horizon/Dockerfile

```dockerfile
FROM stellar/quickstart:testing AS base

FROM ubuntu:22.04

# Dependências: PostgreSQL 14, nginx, stellar-core (para captive), stellar-horizon
RUN apt-get update && apt-get install -y \
    postgresql-14 \
    nginx \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Binários
COPY --from=base /usr/bin/stellar-core /usr/bin/stellar-core
COPY --from=base /usr/bin/stellar-horizon /usr/bin/stellar-horizon
COPY --from=base /usr/lib/x86_64-linux-gnu/lib* /usr/lib/x86_64-linux-gnu/

# Configuração
COPY horizon.env /opt/stellar/horizon/etc/horizon.env
COPY stellar-captive-core.cfg /opt/stellar/horizon/etc/stellar-captive-core.cfg
COPY nginx.conf /etc/nginx/sites-available/default
COPY entrypoint.sh /entrypoint.sh

RUN useradd -m -s /bin/bash stellar && \
    mkdir -p /opt/stellar/horizon /var/run/postgresql && \
    chown -R stellar:stellar /opt/stellar/horizon && \
    chmod +x /entrypoint.sh

VOLUME ["/opt/stellar/horizon", "/var/lib/postgresql"]
EXPOSE 8000 5432

ENTRYPOINT ["/entrypoint.sh"]
```

---

## 8. Sequência de Inicialização

### Container 1: stellar-core (simples)

```
1. entrypoint.sh
2. stellar-core new-db (se primeira vez)
3. stellar-core force-scp (se necessário)
4. stellar-core --conf stellar-core.cfg
5. Aguarda conexão P2P com validadores
6. Catch-up: baixa buckets + checkpoints
7. Entra em modo Synced! / consenso SCP
```

### Container 2: stellar-horizon (mais complexo)

```
1. entrypoint.sh
2. initdb PostgreSQL (se primeira vez)
3. start PostgreSQL
4. createdb horizon
5. horizon db init (migrações)
6. stop PostgreSQL
7. start PostgreSQL (final)
8. start nginx
9. start stellar-horizon
   ├── horizon inicia captive core como subprocesso
   │   └── stellar-core --conf stellar-captive-core.cfg
   └── captive core:
       ├── baixa buckets (~4,3 GB)
       ├── baixa checkpoints
       ├── replay transações
       └── alimenta Horizon via pipe fd:3
10. Horizon ingere metadados no PostgreSQL
11. API disponível na porta 8000
```

### Dependências entre Containers

```yaml
# docker-compose.yml
services:
  stellar-core:
    # ... sem depends_on

  stellar-horizon:
    depends_on:
      stellar-core:
        condition: service_healthy
    # NOTA: Horizon NÃO depende do core para funcionar,
    # mas podemos monitorar o core como referência de status
```

**Nota:** O Horizon NÃO precisa que o Core esteja rodando para funcionar. O `depends_on` é opcional e serve apenas para referência de ordem de inicialização.

---

## 9. Healthchecks

### Core Node

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:11626/info"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 120s
```

### Horizon

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:8001/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 180s
```

---

## 10. Política de Reinicialização

```yaml
stellar-core:
  restart: unless-stopped
  # Se o core travar, o Docker reinicia automaticamente
  # O Horizon continua servindo dados históricos

stellar-horizon:
  restart: unless-stopped
  # Se o Horizon travar, reinicia independentemente do core
```

---

## 11. Comparação de Configurações

### Configuração que PERMANECE IGUAL

| Item | Core | Horizon (captive) |
|:-----|:-----|:------------------|
| `NETWORK_PASSPHRASE` | `Test SDF Network ; September 2015` | `Test SDF Network ; September 2015` |
| `[[VALIDATORS]]` | sdf_testnet_1, 2, 3 | sdf_testnet_1, 2, 3 |
| `HISTORY_ARCHIVE_URLS` | `https://history.stellar.org/...` | `https://history.stellar.org/...` |
| `CATCHUP_RECENT` | 100 | N/A (captive core não usa) |
| `UNSAFE_QUORUM` | true | true |
| `FAILURE_SAFETY` | 1 | 1 |
| `ENABLE_SOROBAN_DIAGNOSTIC_EVENTS` | false | false |

### Configuração que MUDA

| Item | Antes (single) | Depois (core) | Depois (horizon) |
|:-----|:---------------|:---------------|:------------------|
| `HTTP_PORT` | 11626 (core) / 11726 (captive) | 11626 | 11726 |
| `PEER_PORT` | 11625 (core) / 11725 (captive) | 11625 | 11725 |
| `DATABASE` | sqlite3://...core/... (core) / sqlite3://...horizon/... (captive) | sqlite3://... | sqlite3://... (no horizon container) |
| `DATABASE_URL` (Horizon env) | postgres://localhost/horizon | N/A | postgres://localhost/horizon (no mesmo container) |
| `STELLAR_CORE_URL` (Horizon env) | http://localhost:11726 | N/A | http://localhost:11726 (captive core no mesmo container) |
| `PUBLIC_HTTP_PORT` | true (core) / false (captive) | true | false |

---

## 12. Passos para Implementação

### Fase 1: Preparação
- [ ] Criar estrutura de diretórios
- [ ] Extrair configurações atuais do container em execução
- [ ] Identificar versões exatas dos binários (stellar-core v27.1.0, stellar-horizon)

### Fase 2: Container Core
- [ ] Criar Dockerfile para stellar-core
- [ ] Copiar stellar-core.cfg (ajustar paths)
- [ ] Criar entrypoint.sh (new-db, force-scp, init-hist)
- [ ] Testar build e execução isolada

### Fase 3: Container Horizon
- [ ] Criar Dockerfile para stellar-horizon + PostgreSQL
- [ ] Copiar stellar-captive-core.cfg
- [ ] Copiar horizon.env
- [ ] Configurar nginx
- [ ] Criar entrypoint.sh (init db, migrations, start)
- [ ] Testar build e execução isolada

### Fase 4: Orquestração
- [ ] Criar docker-compose.yml
- [ ] Configurar rede Docker
- [ ] Configurar volumes
- [ ] Configurar healthchecks
- [ ] Testar inicialização conjunta

### Fase 5: Validação
- [ ] Verificar se Core atinge Synced!
- [ ] Verificar se Horizon atinge ingestão
- [ ] Verificar isolamento (travar core → horizon continua)
- [ ] Comparar desempenho com single container

---

## 13. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|:------|:-------------|:--------|:----------|
| Captive core não consegue se conectar à rede P2P | Baixa | Alto | Verificar portas de saída, configurar PEER_PORT corretamente |
| Buckets duplicados consomem muito disco | Alta | Médio | Planejar 15 GB+ de espaço, considerar shared volume para buckets no futuro |
| Versões diferentes de stellar-core entre containers | Média | Alto | Usar mesma imagem base para ambos |
| Horizon não consegue iniciar captive core | Baixa | Alto | Verificar STELLAR_CORE_BINARY_PATH, permissões do binário |
| PostgreSQL não inicializa corretamente | Baixa | Alto | Verificar permissões, versão, portas |
| nginx mal configurado | Baixa | Médio | Testar healthcheck do Horizon antes de configurar proxy |
| Perda de dados ao migrar volumes | Média | Alto | Backup dos volumes atuais antes da migração |

---

## 14. Métricas de Sucesso

- [ ] Container Core: `curl http://localhost:11626/info` → `"state": "Synced!"`
- [ ] Container Horizon: `curl http://localhost:8000/` → `"core_latest_ledger"` > 0
- [ ] Core e Horizon estão em ledgers próximos (gap < 100)
- [ ] Parar Core → Horizon continua servindo API com dados históricos
- [ ] Parar Horizon → Core continua no consenso P2P
- [ ] `docker stats` mostra isolamento de recursos entre containers
- [ ] Inicialização completa em < 30 minutos (catch-up)

---

## 15. Próximos Passos

1. ✅ **Fase atual:** Plano de implementação aprovado
2. ⬜ Criar `stellar-core/Dockerfile` e `stellar-core/entrypoint.sh`
3. ⬜ Criar `stellar-horizon/Dockerfile` e `stellar-horizon/entrypoint.sh`
4. ⬜ Criar `docker-compose.yml` completo
5. ⬜ Testar execução local
6. ⬜ Validar métricas e desempenho
7. ⬜ Documentar resultados

---

## Apêndice A: Configurações de Exemplo (extraídas do container atual)

### Core Node Config (`stellar-core.cfg`)
```
HTTP_PORT=11626
PUBLIC_HTTP_PORT=true
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
DATABASE="sqlite3:///opt/stellar/core/stellar.db"
CATCHUP_RECENT=100
UNSAFE_QUORUM=true
FAILURE_SAFETY=1
[[HOME_DOMAINS]]
HOME_DOMAIN="testnet.stellar.org"
QUALITY="HIGH"
[[VALIDATORS]]
NAME="sdf_testnet_1"
PUBLIC_KEY="GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y"
ADDRESS="core-testnet1.stellar.org"
HISTORY="curl -sf http://history.stellar.org/prd/core-testnet/core_testnet_001/{0} -o {1}"
```

### Captive Core Config (`stellar-captive-core.cfg`)
```
HTTP_PORT=11726
PUBLIC_HTTP_PORT=false
PEER_PORT=11725
DATABASE="sqlite3:///opt/stellar/horizon/captive-core/stellar.db"
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
UNSAFE_QUORUM=true
FAILURE_SAFETY=1
```

### Horizon Environment (`horizon.env`)
```
DATABASE_URL=postgres://stellar:<pass>@localhost/horizon
STELLAR_CORE_URL=http://localhost:11726
STELLAR_CORE_BINARY_PATH=/usr/bin/stellar-core
LOG_LEVEL=info
ENABLE_CAPTIVE_CORE_INGESTION=true
CAPTIVE_CORE_USE_DB=true
STELLAR_CAPTIVE_CORE_HTTP_PORT=11726
INGEST=true
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
HISTORY_ARCHIVE_URLS=https://history.stellar.org/prd/core-testnet/core_testnet_001
PORT=8001
CHECKPOINT_FREQUENCY=64
INGEST_DISABLE_STATE_VERIFICATION=True
```

---

## Apêndice B: Diagrama de Rede

```
                     INTERNET
                         │
            ┌────────────┴────────────┐
            │                         │
   history.stellar.org        sdf_testnet{1,2,3}
   (HTTPS 443)                (P2P 11625)
            │                         │
            └────────────┬────────────┘
                         │
              DOCKER HOST (localhost)
                         │
              ┌──────────┴──────────┐
              │                     │
     ┌────────▼────────┐   ┌───────▼────────┐
     │   stellar-core   │   │ stellar-horizon │
     │   172.20.0.10    │   │  172.20.0.11    │
     │                  │   │                 │
     │  ┌────────────┐  │   │ ┌─────────────┐ │
     │  │ P2P 11625  │──┼───┼─│→ saída para │ │
     │  │ HTTP 11626 │  │   │ │ validadores │ │
     │  └────────────┘  │   │ └─────────────┘ │
     │                  │   │                 │
     │  Volume:         │   │ ┌─────────────┐ │
     │  core-data       │   │ │ Captive     │ │
     │                  │   │ │ Core        │ │
     │                  │   │ │ 11725 (P2P) │ │
     │                  │   │ │ 11726 (HTTP)│ │
     │                  │   │ └──────┬──────┘ │
     │                  │   │        │pipe    │
     │                  │   │ ┌──────▼──────┐ │
     │                  │   │ │ Horizon API │ │
     │                  │   │ │ :8001       │ │
     │                  │   │ └──────┬──────┘ │
     │                  │   │        │        │
     │                  │   │ ┌──────▼──────┐ │
     │                  │   │ │ PostgreSQL  │ │
     │                  │   │ │ :5432      │ │
     │                  │   │ └─────────────┘ │
     │                  │   │                 │
     │                  │   │ ┌─────────────┐ │
     │                  │   │ │ nginx :8000 │ │
     │                  │   │ └─────────────┘ │
     │                  │   └─────────────────┘
     └─────────────────┘
```

---

## Apêndice C: docker-compose.yml (rascunho)

```yaml
version: "3.8"

networks:
  stellar-network:
    driver: bridge
    ipam:
      config:
        - subnet: "172.20.0.0/24"

volumes:
  core-data:
  horizon-data:
  pgdata:

services:
  stellar-core:
    build:
      context: ./stellar-core
      dockerfile: Dockerfile
    container_name: stellar-core
    networks:
      stellar-network:
        ipv4_address: 172.20.0.10
    ports:
      - "11625:11625/tcp"
      - "11626:11626/tcp"
    volumes:
      - core-data:/opt/stellar/core
      - core-logs:/var/log/stellar-core
    environment:
      - NETWORK_PASSPHRASE=Test SDF Network ; September 2015
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:11626/info"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s

  stellar-horizon:
    build:
      context: ./stellar-horizon
      dockerfile: Dockerfile
    container_name: stellar-horizon
    networks:
      stellar-network:
        ipv4_address: 172.20.0.11
    ports:
      - "8000:8000/tcp"
    volumes:
      - horizon-data:/opt/stellar/horizon
      - pgdata:/var/lib/postgresql/14/main
    environment:
      - NETWORK=testnet
      - LOG_LEVEL=info
    restart: unless-stopped
    depends_on:
      stellar-core:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 180s
```
