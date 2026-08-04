# 📅 Logbook - Day 12/05

**Focus:** Resolving Ingestion Problems and Robust Synchronization between Nodes

## 🔴 Critical Issue: Horizon Stuck

### Symptoms
* Horizon returning error **503 Still Ingesting** for over 65 minutes.
* Impossible to query accounts or perform transactions.
* Repetitive log: *"waiting for ingestion to catch up"*.

### Root Cause
1.  **Configuration Conflict:** The `docker-compose.yml` had a *custom entrypoint* that tried to modify *Captive Core* configuration files that did not exist at execution time, causing silent failures.
2.  **Volatile Persistence:** The *History Archive* was mapped to `/tmp` (temporary), causing data loss and state inconsistency when restarting the container.

### Applied Solution
We performed a *Hard Reset* and simplified the architecture:

1.  **Deep Cleanup:**
    ```bash
    docker compose down -v
    docker volume prune -f  # Freed 19GB of orphaned data
    docker system prune -f
    rm -rf ./local
    ```
2.  **`docker-compose.yml` Refactoring:**
    * ❌ Removed the problematic custom entrypoint.
    * ❌ Removed unnecessary volume mounts.
    * ✅ Kept only the essential configuration (`VALIDATORS`).
    * ✅ Allowed the Stellar Quickstart to use its internal defaults.

**Result:** Horizon synchronized and became operational in **less than 1 minute** (previously 65+ minutes).

---

## ✅ Automated Transactions

We developed the `scenario_runner.py` script to validate the network using the *Root Account* (bypassing the need for Friendbot for initial operations).

### Test Execution
* **Total:** 10 transactions performed successfully.
* **Flow:**
    1.  Creation of `Acc1` and `Acc2` (10.000 XLM each).
    2.  5 transfers from `Acc2` → `Acc1` (10 XLM each).
    3.  Creation of `Acc3` and `Acc4` (1.000 XLM each).
    4.  5 transfers from `Acc3` → `Acc4` (10 XLM each).

**Generated Accounts:**
* `Acc1`: `GBGH5S2X...BGVW7`
* `Acc2`: `GB2VKHTX...U6G4B`
* `Acc3`: `GDBCG4BI...QOLF`
* `Acc4`: `GC3VRGC3...DVP6O`

---

## 🔄 Peer Node Configuration (212)

### Problem Identified
Node 212 had not been reset properly and had a *gap* of 3500+ ledgers relative to the authoritative node.

### Solution (`docker-compose-peer.yml`)
We created a specific configuration for the node acting:

* **Validation:** `NODE_IS_VALIDATOR=false` (Only observes, does not participate in consensus).
* **Discovery:** `KNOWN_PEERS=["192.168.207.240:11625"]` (Connects directly to the authoritative node).
* **Trust:** `VALIDATORS=["GDKOZJP...YNPN"]` (Trusts the main node).
* **Recovery:** Configured `curl` to download history via HTTP:
    ```bash
    curl -sf [http://192.168.207.240:8000/archive/](http://192.168.207.240:8000/archive/){0}
    ```

### Connectivity Checks
* ✅ Port 11625 accessible.
* ✅ History Archive serving files.
* ✅ `stellar-history.json` available.
* ✅ Docker with correct bindings on `0.0.0.0`.

---

## 📊 Final Network Status

### Node 1 (192.168.207.240) - Authoritative
* ✅ **Ledger:** 3911
* ✅ **State:** Synced!
* ✅ **Horizon:** Operational (Ledger 3885)
* ✅ **Peers:** 2 connected

### Node 2 (192.168.207.212) - Observer
* ✅ **Ledger:** 430 (In Catch-up process)
* ✅ **State:** Synced! (Synchronizing history)
* ✅ **Horizon:** Operational (Ledger 411)
* ✅ **Peers:** 2 connected
* ⏳ **Estimate:** ~20-30 minutes for full parity (Rate: ~3.6 ledgers/sec).

---

## 📈 Day Metrics

| Metric | Value |
| :--- | :--- |
| **Transactions Created** | 10 |
| **Accounts Created** | 4 |
| **Disk Space Freed** | 19.11 GB |
| **Sync Time (Horizon)** | < 1 minute |
| **Current Ledger (Network)** | 3911 |

---

## 📁 Files and Documentation

### Scripts Created
* `scenario_runner.py`: Automation of transaction scenarios.
* `run_more_txs.py`: Robust transactions with fallback to Core.
* `check_sync.sh`: Quick synchronization monitoring between nodes.
* `query_*.py`: Various diagnostic scripts.

### Configurations
* `docker-compose.yml`: Authoritative node (simplified/stable version).
* `docker-compose-peer.yml`: Observer node.

### Docs
* `GUIA_RESET_E_SYNC.md`: Standard procedure to clean the environment.
* `INSTRUCOES_NO_212.md`: Step-by-step guide for the second node.

---

## 🎓 Lessons Learned

### ❌ What Does Not Work
* **Custom Entrypoint on Quickstart:** Causes severe conflicts with Captive Core.
* **History Archive on `/tmp`:** Guarantees data loss on reboots.
* **`sed` on non-existent files:** Generates silent failures that are hard to debug.
* **Isolated Environment Variables:** `KNOWN_PEERS` needs to be injected via script/entrypoint to be correctly recognized by the Core.

### ✅ What Works
* **Default (Vanilla) Configuration:** The Stellar Quickstart is more stable the less it is modified.
* **Full Reset (`down -v` + `prune`):** The only reliable way to resolve inconsistent ledger states.
* **Entrypoint on the Peer:** Essential for setting up network discovery (`KNOWN_PEERS`).
* **Root Account:** More reliable than Friendbot for infrastructure tests.
* **`check_sync.sh` Script:** Quick visual tool for comparing ledger heights.

---

## 🚀 Conclusion
* ✅ Fully functional Stellar private network.
* ✅ Both nodes synchronized and communicating via P2P.
* ✅ Horizon operational and responding to queries on both ends.
* ⏳ Final history synchronization in progress.