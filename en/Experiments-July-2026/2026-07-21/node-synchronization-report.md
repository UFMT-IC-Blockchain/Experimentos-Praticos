# The Synchronization Process of a Stellar Node

When a node on the Stellar network is started and needs to catch up with the current state of the network, it enters a process known as synchronization or *catchup*. This process is not a simple file download, but rather a complex and structured reconstruction of the state of the ledger.

Below, we detail the steps and technical mechanisms that operate behind the scenes during this flow.

## 1. Basic Architecture: Core and Horizon

During synchronization, there are generally two main work fronts operating in a complementary way:

*   **Consensus Engine (Stellar Core):** The base layer, responsible for communicating with the network, downloading the historical state, cryptographically validating the data, and maintaining the official ledger record.
*   **API Server (Horizon):** Acts as the bridge between the node and client applications. It consumes the data validated by Core and ingests it into a relational database, building indexes that enable fast queries (such as the transaction history of an account).

## 2. The Checkpoint Structure

The Stellar network does not transfer history by downloading one *ledger* at a time. To optimize state propagation, the network groups historical data into packages called **checkpoints**. 

Each checkpoint is created every 64 ledgers. Instead of processing transactions one by one in isolation, the node focuses on downloading and applying these consolidated packages. Synchronization progress is measured by the number of checkpoints that still need to be downloaded and processed until the node reaches the target set by the network.

## 3. What Does "Applying" a Checkpoint Mean?

The application phase is the most intensive part of the synchronization process. It transforms the downloaded files into a usable and secure database. This flow consists of four fundamental steps:

### A. Decompression and Parsing
The network state is stored in files called *History Archives*, which use a compressed binary format (`.xdr.gz`). The node first decompresses these files into memory and parses the XDR (External Data Representation) binary structure into objects understandable by the software.

### B. State Merge (Bucket Merge)
State storage in Stellar uses a structure called HAS (*History Archive State*), based on "Buckets". Applying a checkpoint means taking the state contained in the downloaded files and mathematically merging it with the node's current local state. It is a process of replacing, creating and deleting account, balance and offer records that reflects exactly the network snapshot at that moment.

### C. Cryptographic Validation
A fundamental feature of decentralized networks is trust based on mathematics. The node does not blindly trust the downloaded file. After the merge, the node recalculates the SHA-256 hashes of the entire resulting structure. The locally calculated root hash must be identical to the hash approved by the network consensus. This guarantees integrity and confirms that the data has not been tampered with.

### D. Database Ingestion
While Core processes the state, the Horizon service needs to make this data available for queries. This requires that every transaction, effect and operation contained in the checkpoints be written to a relational database (usually PostgreSQL). During this step, thousands of rows are inserted and multiple indexes are created or structurally updated to enable API searches and responses.

## 4. The Nature of the Computational Effort

Advancing checkpoint by checkpoint takes time because it is a continuous, high-cost operation:

*   **Sequentiality:** Processing must occur strictly in order. The node must finish computing, validating and applying the bases of one checkpoint before moving on to the next.
*   **CPU Processing:** The continuous recalculation of hash trees and cryptographic validations consumes massive amounts of processor cycles.
*   **I/O Operations:** Translating this data and massively inserting it into the database generates a very high volume of disk reads and writes, heavily loading the storage layer.

In summary, synchronization is not just copying state; it is a replay and audit mechanism designed so that the node can reconstruct and attest, on its own, to the absolute truth of the network.
