### Candid types of the API

Id of token, e.g. currency
```motoko
type TokenId = nat;
```

Id of aggregator
```motoko
type AggregatorId = nat;
```

Balances are Nats in the smallest unit of the token.
```motoko
type Balance = nat;
```

Subaccount ids are issued in consecutive order, without gaps, starting with 0. Extending the range of subaccount ids is an infrequent administrative action on the ledger carried out by the owner principal of the subaccounts.
```motoko
type SubaccountId = nat;
```

Id of transaction, issued by aggregator. The first value specifies the aggregator who issued the transaction id. The second value (nat) is a locally unique value chosen by the aggregator.
```motoko
type TransactionId = record { AggregatorId; nat };
```

```motoko
type Transaction = vec Part;
```

```motoko
type Batch = vec Transaction;
```

```motoko
type Part = record {
  owner : principal;
  flows : vec Flow;
  memo : opt blob
};
```

```motoko
type Flow = record {
  token : TokenId;
  subaccount : nat;
  amount : int;
};
```

A record of type `Part` is only valid if in the sequence of flows the `subaccount` field is strictly increasing. In particular, there can be at most one flow per subaccount. 

### Ledger API

- #### Get number of aggregators

  **Endpoint**: `nAggregators: () -> (nat) query;`

  **Authorization**: `public`

  **Description**: returns amount of running aggregator canisters

  **Flow**:
  - return `aggregators.size()`

- #### Get aggregator principal

  **Endpoint**: `aggregatorPrincipal: (AggregatorId) -> (principal) query;`

  **Authorization**: `public`

  **Description**: returns principal of selected aggregator. Provided `nat` is an index and has to be in range `0..{nAggregators()-1}`

  **Flow**:
  - return `aggregators[aggregatorId]`
  
- #### Get number of open subaccounts

  **Endpoint**: `nAccounts: () -> (nat) query;`

  **Authorization**: `account owner`

  **Description**: returns the number of open subaccounts for the caller
  
  **Flow**:
  - obtain `ownerId`: `owners.get(msg.caller)`. If it's not defined, return error
  - return `balances[ownerId].size()`

- #### Open new subaccount

  **Endpoint**: `openNewAccounts: (TokenId, nat) -> (SubaccountId);`

  **Authorization**: `account owner`

  **Description**: opens N new subaccounts for the caller and token t. It returns the index of the first new subaccount in the newly created range

  **Flow**:
  - obtain `ownerId`: `owners.get(msg.caller)`. If it's not defined:
    - create it: `ownerId = owners.size()`
    - put to the map: `owners.put(msg.caller, ownerId)`
    - init balances: `balances[ownerId] = []`
  - extract subaccount array `var tokenBalances = balances[ownerId]`
  - remember `tokenBalances.size()`
  - append N new `TokenBalance` entries `{ unit: tokenId, balance: 0}` to `tokenBalances`
  - return original array size

- #### Check balance
  
  **Endpoint**: `balance: (SubaccountId) -> (TokenBalance) query;`

  **Authorization**: `account owner`

  **Description**: returns wallet balance for provided subaccount number

  **Flow**:
  - obtain `ownerId`: `owners.get(msg.caller)`. If it's not defined, return error
  - return `balances[ownerId][subaccountId]`

- #### Process Batch

  **Endpoint**: `processBatch: (Batch) -> (vec TransactionId, nat);`

  **Authorization**: `cross-canister call from aggregator`

  **Description**: processes a batch of newly created transactions. Returns statuses and/or error codes
  
  **Error codes**:
  - (1): account not found
  - (2): subaccount not found
  - (3): token unit mismatch
  - (4): non-sufficient funds
  - (5): token flows do not add up to zero
  - (6): flows are not properly sorted

  **Flow**:
  - check `msg.caller` - should be one of registered aggregators
  - initialize array `result`: can contain either transactionId or error code
  - loop over each `transaction` in `batch`:
    - init cache array of owners `transactionOwners = []` for faster access later
    - init token amount balance map `tokenBalanceMap: Map<TokenId, Int> = ...` for checking that the flows for each 
    token add up to zero
    - loop over each `part` in `transaction` (pass #1: validation):
      - obtain `ownerId`: `owners.get(part.owner)`. If it's not defined, put error code `1` to `result` and continue 
      outer loop. Else push `ownerId` to `transactionOwners` cache array
      - set `last_subaccount` to -1
      - loop over each `flow` in `part`
        - assert that the `flow.subaccount > last_subaccount`. If not set an error code `6` and continue outer loop.
	    - set `last_subaccount` to `flow.subaccount`
        - get appropriate balance: `var tokenBalance = balances[ownerId][flow.subaccount]`. If not found, put error 
        code `2` to `result` and continue outer loop
        - assert `tokenBalance.unit == flow.token` else put error code `3` to `result` and continue outer loop
        - if `tokenBalance.balance + flow.amount < 0`, put error code `4` to `result` and continue outer loop
        - add `flow.amount` to `tokenBalanceMap.get(flow.token)`, if map does not have this token, add it: `tokenBalanceMap.put(flow.token, flow.amount)`
    - loop over `tokenBalanceMap` - if any element != 0, put error code `5` to `result` and continue outer loop
    - loop over each `part` in `transaction`, use `i` as index (pass #2: applying):
      - loop over each `flow` in `part`
        - modify balance: `balances[transactionOwners[i]][flow.subaccount].balance += flow.amount`
  - return `result`

### Aggregator API

- #### Initialize transaction

  **Endpoint**: `submit: (Transaction) -> (variant { Ok: TransactionId ; Err });`

  **Authorization**: `account owner`

  **Description**: initializes transaction: saves it to memory and waits when some principal call `approve` or `reject` on it

  **Flow**:
  - construct `TransactionId`: `{ selfAggregatorIndex, transactionsCounter++ }`
  - construct `TransactionInfo` record: `{ transaction, submiter: msg.caller, status : { #pending [] } }`
  - put transaction info to pending `pendingTransactions.put(transactionId[1], transactionInfo)`
  - return `transactionId`

- #### Approve transaction

  **Endpoint**: `approve: (TransactionId) -> (variant { Ok; Err });`

  **Authorization**: `account owner`

  **Description**: approves transaction by its id

  **Flow**:
  - assert `transactionId[0] == selfAggregatorIndex`, else throw error
  - extract transaction info `var transactionInfo = pendingTransactions.get(transactionId[1])`
  - return error if either:
    - transaction not found 
    - already queued `transactionInfo.status.approved != null`
    - rejected `transactionInfo.status.rejected == true`
  - put `true` to `transactionInfo.status.pending`
  - if approveance is enough to proceed:
    - put to batch queue `approvedTransaction.enqueue(transactionId[1])`
    - set `approvedTransactions.head_number()` to `transactionInfo.status.approved`

- #### Reject transaction

  **Endpoint**: `reject: (TransactionId) -> (variant { Ok; Err });`

  **Authorization**: `account owner`

  **Description**: rejects transaction by its id

  **Flow**:
  - assert `transactionId[0] == selfAggregatorIndex`, else throw error
  - extract transaction info `var transactionInfo = pendingTransactions.get(transactionId[1])`
  - if transaction not found or already queued `transactionInfo.status.approved != null`, return error
  - put `true` to `transactionInfo.status.rejected`

- #### Get transaction status

  **Endpoint**: `transactionDetails: (TransactionId) -> (variant { Ok: TransactionInfo; Err }) query;`

  **Authorization**: `public`

  **Description**: get status of transaction or error code

  **Flow**:
  - return `pendingTransactions.get(transactionId[1])`
