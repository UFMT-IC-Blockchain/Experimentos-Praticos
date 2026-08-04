# Complete Flow of a Transaction on the Stellar Testnet

**Date:** 07/16/2026
**Network:** Test SDF Network ; September 2015
**Container:** stellar-testnet (stellar/quickstart:testing)

---

## Real Transaction Data: 99 XLM (Par1 → Par2)

| Field | Value |
|---|---|
| **Hash** | `9883563f7720b98fa40b81f67c46b68adcaf7f4f3314497269cb98bfe91186c9` |
| **Ledger** | 3646201 |
| **Fee** | 100 stroops (0.00001 XLM) |
| **Sender** | `GA5I2HLH4OIOPDVUYSJCC4JOW7UGFFK43OSVIHLSORPK5YK2CHI7EOLI` |
| **Recipient** | `GAANYRN6WUJHKQ662VEK2YG523HMUUU5WALRAHHD2L465PB5SLF3PR6F` |
| **Amount** | 99 XLM (990,000,000 stroops) |

---

## Step 1 — Construction and Signing (Client)

The user assembles the transaction envelope using the Stellar SDK:

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

Signature generated with the secret key `SD7VQ25L...`:

```
VzmuLe7s0uRxcKAgFSI4oTBXeXJfEgw8XD63rKASAruVPGqldSQLkMnIW//SF+IDtvlzBGtnThSzpQI++nATCg==
```

**Where it occurs:** On the client (Node.js script with `@stellar/stellar-sdk`)
**What travels:** Nothing yet — everything is local in memory

---

## Step 2 — Submission to Horizon

The XDR envelope (base64) is sent via HTTP POST:

```
POST /transactions
Host: http://localhost:8000    (or https://horizon-testnet.stellar.org)
Body: { tx: "AAAAAgAAAAA6jR1n..." }
```

**Where it occurs:** `server.submitTransaction(tx)` in the script
**What travels:** HTTP/1.1 → port 8000 (Nginx) → port 8001 (Horizon)

---

## Step 3 — Horizon Forwards to Captive Core

Horizon queries the Captive Core via HTTP to check whether the transaction is valid before propagating:

```
GET http://localhost:11726    (STELLAR_CORE_URL)
```

The Captive Core (PID 279 on 07/17, or PID 3985 on 07/15) validates:

| Check | Result |
|---|---|
| Correct sequence? (15660283984871425) | ✅ |
| Valid signature? | ✅ |
| Balance ≥ 99 + 0.00001? (10,000 XLM) | ✅ |
| Time bounds not expired? | ✅ |

**Where it occurs:** Inside the container, Horizon → Captive Core
**What travels:** Local HTTP call (localhost:11726)

---

## Step 4 — Captive Core Propagates to the P2P Network

The Captive Core includes the transaction in its **transaction set** and propagates it via **port 11725** to peers and validators:

```
┌─ Captive Core (:11725) ─────────────────────────────┐
│  Includes txHash: 9883563f in the TxSet             │
│  Propagates to:                                     │
│    → sdf_testnet_1 (core-testnet1.stellar.org)      │
│    → sdf_testnet_2 (core-testnet2.stellar.org)      │
│    → sdf_testnet_3 (core-testnet3.stellar.org)      │
│    → random peers (~10 P2P connections)             │
└──────────────────────────────────────────────────────┘
```

**What travels:** SCP messages over TCP :11725
**Protocol:** Stellar P2P (serialized XDR)

---

## Step 5 — SCP Consensus (Stellar Consensus Protocol)

The **SDF validators** process the transaction via SCP in 4 phases. Real data captured from our node (identified as `GA2VM`):

```
Quorum Set: { t: 2, v: [sdf_testnet_1, sdf_testnet_2, sdf_testnet_3] }
Tolerance: f = 1 (FAILURE_SAFETY=1)
Local node:   GA2VM (watcher, does not validate)
```

### Phase 5a — NOMINATE

Each validator proposes its transaction set:

```
sdf_testnet_1: NOMINATE → {txH: 19fa00}
sdf_testnet_2: NOMINATE → {txH: 19fa00}
sdf_testnet_3: NOMINATE → {txH: 19fa00}
```

### Phase 5b — PREPARE

They prepare the ballot with the agreed value:

```
GA2VM (nodes): PREPARE → b: empty_ballot → p: signed_ballot
GA2VM:         PREPARE → b: signed_ballot | c.n: 4294967295
```

### Phase 5c — CONFIRM

They confirm the ballot:

```
GA2VM: CONFIRM → b: signed_ballot | c.n: 1
```

### Phase 5d — EXTERNALIZE

They externalize — ledger closed:

```
sdf_testnet_1: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
sdf_testnet_2: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
sdf_testnet_3: EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
GA2VM (nodes): EXTERNALIZE → c: (1, [SIGNED]) | h.n: 1
```

**3 out of 3 validators agreed → quorum reached ✅**

**What travels:** Signed SCP messages between validators (P2P :11625)
**Participants:** sdf_testnet_1/2/3 + our node as watcher

---

## Step 6 — Closed Ledger (Ledger 3646201)

The ledger closed with 11 successful transactions and 2 failures:

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

Transaction `9883563f` is inside the ledger's **transaction set** (TxSet), identified by the hash `19fa00` in the SCP messages.

---

## Step 7 — Metadata Flows Back

The Captive Core generates execution metadata and sends it via **pipe fd:3** to Horizon:

```
fd:3 ───> Metadata Stream ───> Horizon
```

The decoded XDR metadata shows the state changes:

```
┌─ Ledger 3646201 ─────────────────────────────────────┐
│                                                       │
│  BEFORE:                                               │
│    Par1: 10,000.0000000 XLM                           │
│    Par2: 10,000.0000000 XLM                           │
│                                                       │
│  OPERATION: PAYMENT                                    │
│    source: GA5I2HL...EOLI                             │
│    dest:   GAANYRN...PR6F                             │
│    amount: 99 XLM                                     │
│                                                       │
│  FEE: 100 stroops (0.00001 XLM)                       │
│    debited from Par1 (source account)                 │
│                                                       │
│  AFTER:                                                │
│    Par1:  9,900.9999900 XLM                           │
│    Par2: 10,099.0000000 XLM                           │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

## Step 8 — Horizon Persists to PostgreSQL

Horizon processes the metadata stream and persists it to the database:

```sql
-- History tables
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

-- Effects
INSERT INTO history_effects (account, type, amount)
  VALUES ('GA5I2HL...EOLI', 'account_debited', '99.0000000');

INSERT INTO history_effects (account, type, amount)
  VALUES ('GAANYRN...PR6F', 'account_credited', '99.0000000');

-- State tables (accounts)
UPDATE accounts
SET balance = balance - 99.0000100
WHERE account_id = 'GA5I2HL...EOLI';

UPDATE accounts
SET balance = balance + 99.0000000
WHERE account_id = 'GAANYRN...PR6F';
```

---

## Step 9 — Confirmation to the User

Horizon responds to the POST with:

```json
{
  "hash": "9883563f7720b98fa40b81f67c46b68adcaf7f4f3314497269cb98bfe91186c9",
  "ledger": 3646201,
  "successful": true,
  "result_xdr": "AAAAAAAAAGQAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAA="
}
```

The ResultXDR indicates: **txSUCCESS** (code 0)

---

## Visual Map of the Complete Flow

```
YOU (Node.js client)
│
│ 1. Creates + signs TransactionEnvelope
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
│ 3. Validates → forwards to Captive Core
│    STELLAR_CORE_URL=http://localhost:11726
│
▼
CAPTIVE CORE (PID 279, P2P :11725)
│
│ 4. Includes in TxSet → propagates via P2P
│
▼
┌──────────────────────────────────────────────────────────┐
│                  TESTNET NETWORK (P2P)                    │
│                                                           │
│   sdf_testnet_1 ──╮                                       │
│   sdf_testnet_2 ──╬── SCP Consensus (4 phases)            │
│   sdf_testnet_3 ──╯    NOMINATE → PREPARE                 │
│                         → CONFIRM → EXTERNALIZE            │
│                                                           │
│   5. Quorum: 3/3 valid ✅                                 │
└──────────────────────────────────────────────────────────┘
│
│ 6. Ledger 3646201 closed
│    TxSet includes hash 9883563f
│
▼
CAPTIVE CORE (PID 279)
│
│ 7. Metadata stream via fd:3
│    { Par1: 9,900.99999 XLM, Par2: 10,099 XLM }
│
▼
HORIZON
│
│ 8. INSERT / UPDATE in PostgreSQL
│    history_transactions, operations, effects
│    accounts (debited/credited balance)
│
▼
POSTGRESQL (33 tables, ~1.2 GB)
│
│ 9. Confirmation: HTTP 200 + ResultXDR
│
▼
YOU: "Transaction sent! Hash: 9883563f"
```

---

## Time Summary

| Step | Where | Estimated Time |
|---|---|---|
| 1-2 | Client → Horizon API | ~100 ms |
| 3 | Horizon → Captive Core | ~5 ms (localhost) |
| 4 | Captive → P2P Network | ~50 ms |
| 5 | SCP Consensus | ~2-5 s (until next ledger) |
| 6 | Closed ledger | Instantaneous |
| 7-8 | Captive → Horizon → PostgreSQL | ~50 ms |
| **Total** | **User → Confirmation** | **~3-5 seconds** |

---

## Components Involved

| Component | PID | Ports | Role in the Flow |
|---|---|---|---|
| **Your script** | — | — | Creates, signs, and submits the transaction |
| **Nginx** | 288 | :8000 | Reverse proxy for Horizon |
| **Horizon** | 170 | :8001 | Receives POST, coordinates ingestion |
| **Captive Core** | 279 | :11725 P2P, :11726 HTTP | Propagates tx, downloads state, metadata stream |
| **Stellar Core Node** | 121 | :11625 P2P, :11626 HTTP | Consensus watcher (not used directly) |
| **PostgreSQL** | 163 | :5432 | Persists history and state |
| **sdf_testnet_1/2/3** | — | :11625 | Validators running SCP |
| **P2P Peers** | — | :11625 / :11725 | Relay SCP messages |

---

> **Example transactions:** `9883563f` (99 XLM Par1→Par2 via public) and `11c67c66` (50 XLM Par2→Par1 via local)  
> **Report generated on:** 07/16/2026
