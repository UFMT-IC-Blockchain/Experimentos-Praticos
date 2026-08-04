# 📅 Logbook - Day 04

**Focus:** Advanced Stellar Private Network Configuration (Interconnection and Synchronization)

## ✅ Activities Completed

### 1. Main Node Preparation (gambyte2 - 192.168.207.212)
* **Peers Automation:** We implemented an entrypoint script in the `docker-compose.yml` to automatically inject the `KNOWN_PEERS` configuration, ensuring the node knows where to find its peers at startup.
* **Security and Network:** We configured the Firewall (UFW) to open the essential ports:
  * `8000`: Horizon API (for queries and transactions).
  * `11625`: P2P Protocol (for communication between Stellar Core nodes).
  * `11626`: HTTP Info (for Core diagnostics).
* **Solution for History Archive Files:**
  * **Challenge:** The Stellar Quickstart in local mode does not expose the history archive files publicly, which prevents other nodes from performing the "catchup" (initial synchronization).
  * **Solution:** We configured the container's internal Nginx to serve the history folder (`/tmp/stellar-core/history/vs`) through port 8000. This allowed the secondary node to download the old blocks via HTTP.

### 2. Secondary Node Configuration (gambyte1 - Local)
* **Isolation Resolution (Consensus):**
  * **Challenge:** The node connected to the peer, but did not synchronize because it only trusted itself (`VALIDATORS=["$self"]`).
  * **Solution:** We updated the `docker-compose.yml` to include the main node ID (`GCTI6...`) in the validators list. This instructed the local node to accept the blocks validated by the main node.
* **History Download Configuration:**
  * **Challenge:** The node got stuck in the "Catching up" state because it tried to copy history files locally (`cp`), but they were on the other computer.
  * **Solution:** We modified the `stellar-core.cfg` to use the `curl` command, pointing to the HTTP endpoint configured on the main node (`http://192.168.207.212:8000/archive/{0}`).
* **Result:** The node completed the buckets download and transitioned to the **"Synced!"** state.

### 3. Transaction Tests and Scripts
* We developed scripts to make network usage easier:
  * `create-account-and-fund.sh`: Automates key creation and funding via Friendbot.
  * `transaction_example.py`: Robust Python script to perform payments.
* **Proof of Concept:** We performed a **50 XLM** transfer between two accounts (Alice and Bob) created on our private network, confirming that consensus and transaction propagation are working perfectly.

## 📊 Current Network Status

### Synchronization
* Both nodes are **100% synchronized**, sharing the same ledger.
* The local node (gambyte1) acts as an observer validator of the main node (gambyte2).

### Available Services
* **Horizon API:** Accessible on both machines. The local node is finishing the ingestion of historical data to allow complete queries.
* **Friendbot:** Operational on the main node, allowing instant creation of test accounts.

### Infrastructure
* The network now supports both real-time synchronization (via port 11625) and history recovery (via port 8000).

## 🚧 Next Steps

* **Final Validation:** Confirm that the local node's Horizon correctly displays the transaction history after ingestion finishes.
* **Resilience:** Test the network behavior when restarting the nodes to ensure the configurations (especially Nginx and `stellar-core.cfg`) persist correctly.
* **Expansion:** Evaluate adding a third node to test more complex quorum scenarios.