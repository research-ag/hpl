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

