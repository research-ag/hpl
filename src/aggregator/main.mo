import { nyi; xxx } "mo:base/Prelude";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// aggregator
// the constructor arguments are:
//   principal of the ledger canister
//   own aggregator id
// the constructor arguments are passed like this:
//   dfx deploy --argument='(principal "aaaaa-aa")' aggregator 
// alternatively, the argument can be placed in dfx.json according to this scheme:
// https://github.com/dfinity/sdk/blob/ca578a30ea27877a7222176baea3a6aa368ca6e8/docs/dfx-json-schema.json#L222-L229
actor class Aggregator(_ledger : Principal, own_id : Nat) {

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type Transaction = T.Transaction;
  type TransactionId = T.TransactionId;

  // 
  type QueueNumber = Nat;
  type Approvals = [Bool];
  type TransactionInfo = {
    id : TransactionId;
    submitter : Principal;
    status : { #pending : Approvals; #approved : QueueNumber; #rejected };
  };
 
  // canister id of the ledger canister
  let ledger : Principal = _ledger; 
 
  // the own unique identifier of this aggregator
  var selfAggregatorIndex: Nat = own_id;

  // We track transactions counter:
  var transactionsCounter: Nat = 0;

  /*
The main concern of the aggregator is the potential situation that it has too many approved transactions: we limit Batch 
size so the aggregator should be able to handle case when it has more newly approved transactions than batch limit between 
ticks. To avoid this, we could use [FIFO queue](https://github.com/o0x/motoko-queue) data structure for saving approved transactions. 
In this case we will transmit to ledger older transactions and keep newer in the queue, waiting for next tick. As a value 
in the queue, we use second `Nat` from `TransactionId`
import Queue "Queue";

var approvedTransactions: Queue.Queue<Nat> = Queue.nil();
```
  */

  // updates

  type SubmitError = { #NoSpace; #Invalid; };
  public func submit(transfer: Transaction): async Result<TransactionId, SubmitError> {
    nyi();
  };

  type NotPendingError = { #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public func approve(transferId: TransactionId): async Result<(),NotPendingError> {
    nyi();
  };

  public func reject(transferId: TransactionId): async Result<(),NotPendingError> {
    nyi();
  };

  type TransactionError = { #NotFound; };
  public query func txDetails(transferId: TransactionId): async Result<TransactionInfo, TransactionError> {
    nyi();
  };

  // admin interface

  // set own aggregator id
  public func set_id(id : Nat) {
    nyi();
  };
};
