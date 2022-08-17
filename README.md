<h1 align="center">
    
     __  __     ______   __        
    /\ \_\ \   /\  == \ /\ \       
    \ \  __ \  \ \  _-/ \ \ \____  
     \ \_\ \_\  \ \_\    \ \_____\
      \/_/\/_/   \/_/     \/_____/
</h1>

<h4 align="center">A high performance ledger on the Internet Computer.</h4>

<p align="center">
  <a href="#about">About</a> •
  <a href="#features">Features</a> •
  <a href="#api">API</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#deployment">Deployment</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#credits">Credits</a> •
  <a href="#support">Support</a> •
  <a href="#license">License</a>
</p>

---

## About

The goal is to design and demonstrate a ledger on the IC that can handle 10,000 transactions per second which are submitted individually by different end users via ingress messages. The number of ingress messages that the consensus mechanism of a single subnet can process is only in the order of 1,000 per second and is in fact rate limited by boundary nodes to 400 per second. Therefore, to get to the desired throughput we need to utilize 25 subnets.

The approach we take is based on the assumption that consensus is indeed the bottleneck and that computation and memory are not bottlenecks. Our approach has a single ledger canister which stores all account balances and settles all transactions. Transactions are not submitted to the ledger directly, though. Instead, end users submit their transactions to aggregators of which there are 25, all on different subnets. Aggregators batch up the transactions and forward them in batches to the ledger. The bottleneck is now the block space available for incoming cross-subnet messages on the subnet that hosts the ledger. If the size of a simple transfer is 100 bytes then each aggregator submits 40kB of data per second to the ledger. For all aggregators combined this occupies 1 MB of block space per second.

With some compression techniques we expect that the size of a simple transfer can be reduced to be around 20 bytes, which means a block space requirement of only 200 kB per second.

We expect the computational resources required to check 10,000 account balances and update 20,000 account balances per second to be within what a single canister can do.

We expect the memory resources required to store 100 million account balances to be within what a single canister can do.

We do not expect the ledger to be able to store the history of transactions, but this is not an argument against the design of having a single ledger canister. In fact, even distributing the ledger over 25 subnets would not change the fact that storing the entire history of transactions on chain is impossible. At 10,000 tps and 20 bytes per transaction the history grows by >500 GB per month. Therefore we propose to store only recent history in the ledger canister. The entire history has to be archived off chain but can always be authenticated against root hashes that are stored in the ledger.

## Features

TBD

## API

TBD

## Architecture

<p align="center">
    <img src=".github/assets/context.drawio.png" alt="Context diagram" style="width: 100%"/>
    <br/><span style="font-style: italic">context diagram</span>
</p>

With **HPL**, registered principals can initiate, process and confirm multi-token transfers. **HPL** charges fee for transfer

**Note**: Accounts for principals need to be explicitly opened by the owner.

### High-level user story:

1. Registered **HPL** principals **A** and **B** communicate directly to agree on the transfer details and on who initiates the transfer  (say **A**). 
2. **A** creates transfer on **HPL** and receives generated **transferId** as response
3. **A** sends **transferId** to **B** directly
4. **B** calls **HPL** with **tranferId** to accept the transfer
5. **HPL** asynchronously processes the transfer
6. **A** and **B** can query HPL about the status of transfer (processing, success, failed)

---
<p align="center">
    <img src=".github/assets/container.drawio.png" alt="Container diagram" style="width: 100%"/>
    <br/><span style="font-style: italic">container diagram</span>
</p>

**HPL** infrastructure consists of 1 **Ledger** and N **Aggregators**. N == 25 by default
- **Aggregator** canister is an entrypoint for principals. During the transfer process, both sender and receiver principal have to use one single aggregator. The aggregator is responsible for:
    - principals authentication
    - initial transfer validation
    - charging fee
    - sending batched prepared transfers to the **Ledger**
    - receiving confirmation from the **ledger** for each transfer
    - serving transfer status to principals
- **Ledger** canister has the complete token ledger. It is the single source of truth on account balances. It settles all transfers. It cannot be called directly by principals. The ledger is responsible for:
  - receiving batched transfers from aggregators
  - validation of each transfer
  - save all account balances
  - save latest transfers

### Low-level user story:
TODO add links to API when documented

1. Registered **HPL** principals **A** and **B** communicate directly to agree on the transfer details and on who initiates the transfer  (say **A**).
2. **A** chooses aggregator **G**
3. **A** calls a function on **G** with the transfer details
4. **G** charges **A** a fee for storing a pending transfer, aborts if charging the fee fails
5. **G** generates a **transferId** and stores the pending transfer under this id
6. **G** returns **transferId** to **A** as response
7. **A** sends **transferId** to **B** directly
8. **B** calls **G** with **tranferId** to accept the transfer
9. **G** puts the transfer in the next batch
10. At the next heartbeat, **G** sends a batch of transfers in a single cross-canister call to the ledger **L**
11. **L** processes the transfers in the batch in order, i.e. executes the transfer if valid and discards it if invalid
12. **L** returns the list of successfully executed transfer ids to **G**
13. **A** and **B** can query **G** about the status of transfer (processing, success, failed)

<p align="center">
    <img src=".github/assets/flow.drawio.png" alt="Container diagram" style="width: 100%"/>
</p>

## Deployment

TBD


## Contributing

TBD

## Credits

TBD

## Support

TBD

## License

TBD
