import { nyi; xxx } "mo:base/Prelude";
import Deque "mo:base/Deque";

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
  let selfAggregatorIndex: Nat = own_id;

  // We track transactions counter:
  var transactionsCounter: Nat = 0;

  /*
  The aggregator sends the transactions in batches to the ledger. It does so at every invocation by the heartbeat functionality.
  Between heartbeats, approved transaction queue up and get stored in Deque. The batches have a size limit. At every heartbeat, 
  we pop as many approved transactions from the queue as fit into a batch and send the batch.

  In a future iteration we can send more than one batch per heartbeat. But this approach requires a mechanism to slow down when 
  delivery failures occur. 

  The deque is of type Deque<Transaction>. This results in pointers to Transactions that are stored in the Trie already. 
  When a Transaction is removed from the Deque and the Trie (i.e. dereferenced) then the garbage collector will delete it.
  */

  var approvedTransactions = Deque.empty<Transaction>();

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
