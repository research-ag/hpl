# Welcome to the High Performance Ledger

This documentation resides on [GitHub Pages](https://research-ag.github.io/hpl/).

# About

The goal is to design and demonstrate a ledger on the [Internet Computer](https://internetcomputer.org/) that can handle 10,000 transactions per second which are submitted individually by different end users via ingress messages. The number of ingress messages that the consensus mechanism of a single subnet can process is only in the order of 1,000 per second and is in fact rate limited by boundary nodes to a lower number (maybe around 400 per second). Therefore, to get to the desired throughput we plan to utilize 25 subnets.

The approach we take is based on the assumption that consensus is indeed the bottleneck and that computation and memory are not bottlenecks. Our approach has a single ledger canister which stores all account balances and settles all transactions. Transactions are not submitted to the ledger directly, though. Instead, end users submit their transactions to aggregators of which there are 25, all on different subnets. Aggregators batch up the transactions and forward them in batches to the ledger. The bottleneck is now the block space available for incoming cross-subnet messages on the subnet that hosts the ledger. If the size of a simple transaction is 100 bytes then each aggregator submits 40kB of data per second to the ledger. For all aggregators combined this occupies 1 MB of block space per second.

With some compression techniques we expect that the size of a simple transaction can be reduced to be around 20 bytes, which means a block space requirement of only 200 kB per second.

We expect the computational resources required to check 10,000 account balances and update 20,000 account balances per second to be within what a single canister can do.

We expect the memory resources required to store 100 million account balances to be within what a single canister can do.

We do not expect the ledger to be able to store the history of transactions, but this is not an argument against the design of having a single ledger canister. In fact, even distributing the ledger over 25 subnets would not change the fact that storing the entire history of transactions on chain is impossible. At 10,000 tps and 20 bytes per transaction the history grows by >500 GB per month. Therefore we propose to store only recent history in the ledger canister. The entire history has to be archived off chain but can always be authenticated against root hashes that are stored in the ledger.

# Features

The ledger is a multi-token ledger. This means that multiple tokens, differentiated from each other by a token id, can be hosted on the same ledger canister.

All transactions need to be explicitly approved by all parties involved, even the receiver. There are no deposits into arbitrary accounts without approval of the receiver.

Multiple token flows can happen atomically in a single transaction.

More than two parties can be part of a single transaction and all have to approve.

Any party can initiate the transaction: the sender, the receiver or even a third-party. The initiator is paying the fee.

# API

## Terminology

**Canister** - conceptual computational unit, executes program in the Internet Computer blockchain [Read More](https://wiki.internetcomputer.org/wiki/Canisters_(dapps/smart_contracts))

**Principal** - an identifier for an entity on the IC such as a user, a canister (dapps/smart contracts), or a subnet. [Read More](https://wiki.internetcomputer.org/wiki/Principal)

**Subaccount** - essentially a wallet, owned by one principal and containing one type of tokens. Client principal can have many subaccounts with different and/or the same tokens 

## Candid types of the API

See source files [ledger.did](https://github.com/research-ag/hpl/blob/main/src/ledger/ledger.did) and [aggregator.did](https://github.com/research-ag/hpl/blob/main/src/aggregator/aggregator.did).
