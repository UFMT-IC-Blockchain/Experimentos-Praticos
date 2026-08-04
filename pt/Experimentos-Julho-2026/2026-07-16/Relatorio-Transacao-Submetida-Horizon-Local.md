# Fluxo Completo de uma Transação na Stellar Testnet

**Data:** 16/07/2026
**Rede:** Test SDF Network ; September 2015
**Container:** stellar-testnet (stellar/quickstart:testing)

---

## Dados Reais da Transação: 99 XLM (Par1 → Par2)

| Campo | Valor |
|---|---|
| **Hash** | `9883563f7720b98fa40b81f67c46b68adcaf7f4f3314497269cb98bfe91186c9` |
| **Ledger** | 3646201 |
| **Taxa** | 100 stroops (0,00001 XLM) |
| **Remetente** | `GA5I2HLH4OIOPDVUYSJCC4JOW7UGFFK43OSVIHLSORPK5YK2CHI7EOLI` |
| **Destinatário** | `GAANYRN6WUJHKQ662VEK2YG523HMUUU5WALRAHHD2L465PB5SLF3PR6F` |
| **Valor** | 99 XLM (990.000.000 stroops) |

---

## Etapa 1 — Construção e Assinatura (Cliente)

O usuário monta o envelope da transação usando o SDK Stellar:

```json
{
  "sourceAccount": "GA5I2HLH4OIOPDVUYSJCC4JOW7UGFFK43OSVIHLSORPK5YK2CHI7EOLI",
  "fee": 100,
  "seqNum": 15660283984871425,
  "cond": { "timeBounds": { "minTime": 0, "maxTime": 1784248008 } },
  "operations": [{
    "body": {
      "type": "PAYMENT",
      "paymentOp": {
        "destination": "GAANYRN6WUJHKQ662VEK2YG523HMUUU5WALRAHHD2L465PB5SLF3PR6F",
        "asset": "NATIVE",
        "amount": 990000000
      }
    }
  }]
}
```

Assinatura gerada com a secret key `SD7VQ25L...`:

```
VzmuLe7s0uRxcKAgFSI4oTBXeXJfEgw8XD63rKASAruVPGqldSQLkMnIW//SF+IDtvlzBGtnThSzpQI++nATCg==
```

**Onde ocorre:** No cliente (script Node.js com `@stellar/stellar-sdk`)
**O que trafega:** Nada ainda — tudo local na memória

---

## Etapa 2 — Submissão ao Horizon

O envelope XDR (base64) é enviado via HTTP POST:

```
POST /transactions
Host: http://localhost:8000    (ou https://horizon-testnet.stellar.org)
Body: { tx: "AAAAAgAAAAA6jR1n..." }
```

**Onde ocorre:** `server.submitTransaction(tx)` no script
**O que trafega:** HTTP/1.1 → porta 8000 (Nginx) → porta 8001 (Horizon)

---

## Etapa 3 — Horizon Encaminha ao Captive Core

O Horizon consulta o Captive Core via HTTP para verificar se a transação é válida antes de propagar:

```
GET http://localhost:11726    (STELLAR_CORE_URL)
```

O Captive Core (PID 279 no dia 17/07, ou PID 3985 no dia 15/07) valida:

| Verificação | Resultado |
|---|---|
| Sequência correta? (15660283984871425) | ✅ |
| Assinatura válida? | ✅ |
| Saldo ≥ 99 + 0,00001? (10.000 XLM) | ✅ |
| Time bounds não expirado? | ✅ |

**Onde ocorre:** Dentro do container, Horizon → Captive Core
**O que trafega:** Chamada HTTP local (localhost:11726)

---

## Etapa 4 — Captive Core Propaga para a Rede P2P

O Captive Core inclui a transação no seu **transaction set** e propaga via **porta 11725** para peers e validadores:

```
┌─ Captive Core (:11725) ─────────────────────────────┐
│  Inclui txHash: 9883563f no TxSet                    │
│  Propaga para:                                        │
│    → sdf_testnet_1 (core-testnet1.stellar.org)        │
│    → sdf_testnet_2 (core-testnet2.stellar.org)        │
│    → sdf_testnet_3 (core-testnet3.stellar.org)        │
│    → peers aleatórios (~10 conexões P2P)              │
└──────────────────────────────────────────────────────┘
```

**O que trafega:** Mensagens SCP sobre TCP :11725
**Protocolo:** Stellar P2P (XDR serializado)

---

## Etapa 5 — Consenso SCP (Stellar Consensus Protocol)

Os **validadores SDF** processam a transação via SCP em 4 fases. Dados reais capturados do nosso nó (identificado como `GA2VM`):

```
Quorum Set: { t: 2, v: [sdf_testnet_1, sdf_testnet_2, sdf_testnet_3] }
Tolerância: f = 1 (FAILURE_SAFETY=1)
Nó local:   GA2VM (watcher, não valida)
```

### Fase 5a — NOMINATE

Cada validador propõe seu transaction set:

```
sdf_testnet_1: NOMINATE → {txH: 19fa00}
sdf_testnet_2: NOMINATE → {txH: 19fa00}
sdf_testnet_3: NOMINATE → {txH: 19fa00}
```

### Fase 5b — PREPARE

Preparam o ballot com o valor acordado:

```
GA2VM (nós): PREPARE → b: ballot_vazio → p: ballot_assinado
GA2VM:        PREPARE → b: ballot_assinado | c.n: 4294967295
```

### Fase 5c — CONFIRM

Confirmam o ballot:

```
GA2VM: CONFIRM → b: ballot_assinado | c.n: 1
```

### Fase 5d — EXTERNALIZE

Externalizam — ledger fechado:

```
sdf_testnet_1: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
sdf_testnet_2: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
sdf_testnet_3: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
GA2VM (nós):   EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
```

**3 de 3 validadores concordaram → quorum atingido ✅**

**O que trafega:** Mensagens SCP assinadas entre validadores (P2P :11625)
**Participantes:** sdf_testnet_1/2/3 + nosso nó como watcher

---

## Etapa 6 — Ledger Fechado (Ledger 3646201)

O ledger é fechado com 11 transações bem-sucedidas e 2 falhas:

```json
{
  "sequence": 3646201,
  "closed_at": "2026-07-17T00:25:50Z",
  "successful_transaction_count": 11,
  "failed_transaction_count": 2,
  "operation_count": 13,
  "total_coins": "100000000000.0000000",
  "fee_pool": "400254.6640480",
  "base_fee_in_stroops": 100
}
```

A transação `9883563f` está dentro do **transaction set** (TxSet) do ledger, identificado pelo hash `19fa00` nas mensagens SCP.

---

## Etapa 7 — Metadados Fluem de Volta

O Captive Core gera metadados da execução e envia via **pipe fd:3** para o Horizon:

```
fd:3 ───> Metadata Stream ───> Horizon
```

O metadado XDR decodificado mostra as mudanças de estado:

```
┌─ Ledger 3646201 ─────────────────────────────────────┐
│                                                       │
│  ANTES:                                                │
│    Par1: 10.000,0000000 XLM                           │
│    Par2: 10.000,0000000 XLM                           │
│                                                       │
│  OPERAÇÃO: PAYMENT                                     │
│    source: GA5I2HL...EOLI                             │
│    dest:   GAANYRN...PR6F                             │
│    amount: 99 XLM                                     │
│                                                       │
│  TAXA: 100 stroops (0,00001 XLM)                      │
│    debitado de Par1 (source account)                  │
│                                                       │
│  DEPOIS:                                               │
│    Par1:  9.900,9999900 XLM                           │
│    Par2: 10.099,0000000 XLM                           │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

## Etapa 8 — Horizon Persiste no PostgreSQL

O Horizon processa o stream de metadados e persiste no banco:

```sql
-- Tabelas de histórico
INSERT INTO history_transactions VALUES (
  hash='9883563f...86c9',
  ledger=3646201,
  source='GA5I2HL...EOLI',
  fee=100,
  successful=true
);

INSERT INTO history_operations VALUES (
  id=15660314049658881,
  transaction_hash='9883563f...86c9',
  type='payment',
  source='GA5I2HL...EOLI',
  details={ from, to, amount: '99.0000000' }
);

-- Efeitos
INSERT INTO history_effects (account, type, amount)
  VALUES ('GA5I2HL...EOLI', 'account_debited', '99.0000000');

INSERT INTO history_effects (account, type, amount)
  VALUES ('GAANYRN...PR6F', 'account_credited', '99.0000000');

-- Tabelas de estado (accounts)
UPDATE accounts
SET balance = balance - 99.0000100
WHERE account_id = 'GA5I2HL...EOLI';

UPDATE accounts
SET balance = balance + 99.0000000
WHERE account_id = 'GAANYRN...PR6F';
```

---

## Etapa 9 — Confirmação ao Usuário

O Horizon responde ao POST com:

```json
{
  "hash": "9883563f7720b98fa40b81f67c46b68adcaf7f4f3314497269cb98bfe91186c9",
  "ledger": 3646201,
  "successful": true,
  "result_xdr": "AAAAAAAAAGQAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAA="
}
```

O ResultXDR indica: **txSUCCESS** (código 0)

---

## Mapa Visual do Fluxo Completo

```
VOCÊ (cliente Node.js)
│
│ 1. Cria + assina TransactionEnvelope
│    { source: Par1, dest: Par2, amount: 99 XLM }
│
▼
HORIZON API (localhost:8000 → Nginx → :8001)
│
│ 2. POST /transactions
│
▼
HORIZON SERVER (PID 170)
│
│ 3. Valida → encaminha para Captive Core
│    STELLAR_CORE_URL=http://localhost:11726
│
▼
CAPTIVE CORE (PID 279, P2P :11725)
│
│ 4. Inclui no TxSet → propaga via P2P
│
▼
┌──────────────────────────────────────────────────────────┐
│                  REDE TESTNET (P2P)                       │
│                                                           │
│   sdf_testnet_1 ──╮                                       │
│   sdf_testnet_2 ──╬── SCP Consensus (4 fases)             │
│   sdf_testnet_3 ──╯    NOMINATE → PREPARE                 │
│                         → CONFIRM → EXTERNALIZE            │
│                                                           │
│   5. Quorum: 3/3 válido ✅                                │
└──────────────────────────────────────────────────────────┘
│
│ 6. Ledger 3646201 fechado
│    TxSet inclui hash 9883563f
│
▼
CAPTIVE CORE (PID 279)
│
│ 7. Metadata stream via fd:3
│    { Par1: 9.900,99999 XLM, Par2: 10.099 XLM }
│
▼
HORIZON
│
│ 8. INSERT / UPDATE no PostgreSQL
│    history_transactions, operations, effects
│    accounts (saldo debitado/creditado)
│
▼
POSTGRESQL (33 tabelas, ~1,2 GB)
│
│ 9. Confirmação: HTTP 200 + ResultXDR
│
▼
VOCÊ: "Transação enviada! Hash: 9883563f"
```

---

## Resumo dos Tempos

| Etapa | Onde | Tempo Estimado |
|---|---|---|
| 1-2 | Cliente → Horizon API | ~100 ms |
| 3 | Horizon → Captive Core | ~5 ms (localhost) |
| 4 | Captive → Rede P2P | ~50 ms |
| 5 | SCP Consensus | ~2-5 s (até próximo ledger) |
| 6 | Ledger fechado | Instantâneo |
| 7-8 | Captive → Horizon → PostgreSQL | ~50 ms |
| **Total** | **Usuário → Confirmação** | **~3-5 segundos** |

---

## Componentes Envolvidos

| Componente | PID | Portas | Função no Fluxo |
|---|---|---|---|
| **Seu script** | — | — | Cria, assina e submete a transação |
| **Nginx** | 288 | :8000 | Reverse proxy para o Horizon |
| **Horizon** | 170 | :8001 | Recebe POST, coordena ingestão |
| **Captive Core** | 279 | :11725 P2P, :11726 HTTP | Propaga tx, baixa estado, stream de metadados |
| **Stellar Core Node** | 121 | :11625 P2P, :11626 HTTP | Watcher do consenso (não usado diretamente) |
| **PostgreSQL** | 163 | :5432 | Persiste histórico e estado |
| **sdf_testnet_1/2/3** | — | :11625 | Validadores executam SCP |
| **Peers P2P** | — | :11625 / :11725 | Retransmitem mensagens SCP |

---

> **Transações de exemplo:** `9883563f` (99 XLM Par1→Par2 via público) e `11c67c66` (50 XLM Par2→Par1 via local)  
> **Relatório gerado em:** 16/07/2026
