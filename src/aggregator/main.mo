import { nyi; xxx } "mo:base/Prelude";
import Deque "mo:base/Deque";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import List "mo:base/List";

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

  /*
  We track how many transactions were submitted, queued and batched in three counters.
  The values of the first two counters are associated with a transaction the moment it is submitted and queued (pushed).
  The value of the "submitted" counter becomes the "submit number" of the transaction.
  The value of the "queued" counter becomes the "queue number" of the transaction.
  The values are captured before the counters are incremented, i.e. the numbering is 0-based in both cases.
  The submit number reflects the order in which transactions were submitted,
  the queue number reflects the order in which transactions became fully approved.
  The submit number together with the aggregator id becomes the globally unique transaction id.
  The value of the batched counter equals the number of elements that have been popped from the queue since the beginning.
  Thus, it is equal to the queue number of the transaction that sits at the head of the queue. 
  Hence, a transaction's queue number minus the "batched" counter specifies how far the transaction is from the head of the queue. 
  */
 
  var submitted : Nat = 0;
  var queued : Nat = 0;
  var batched : Nat = 0;

  /* 
  Here is the information that we store for each transaction while we are holding the transaction
  `Approvals` is a vector that captures the information who has already approved the transaction.
  The vector's length equals the number of contributors to the transactions.
  */
  type SubmitNumber = Nat;
  type QueueNumber = Nat;
  type Approvals = [Bool];
  type TransactionRequest = {
    transaction : Transaction;
    submitter : Principal;
    submit_number : SubmitNumber;
    status : { #pending : Approvals; #approved : QueueNumber; #rejected : Bool  };
  };

  /* 
  Pending transactions are being stored in an "ordered pool" of bounded size. The pool allows to
    - add a new element 
    - delete the oldest element (without the caller knowing which one that is)
    - delete any element provided by the caller
  For example code how to build this data structure with a doubly-linked list see pool.mo.

  If there is no space for a new element then the oldest one in the pool gets overwritten by deleting it first. 
  When a transaction is fully approved then it is removed from the pool and placed in the queue.
  We track the overall number of transactions in the aggregator from pool plus queue with a counter. 
  If the counter reaches the maximum then new submissions are denied.

  In the first implementation there is only one global pool. 
  In the future, submitting principals can have their own pool if they pay fees for it.
  */

  // If 256 new transactions are submitted per second and never approved then in a pool of size 2**24 they last for ~18h before they get overwritten. 
  let max_transactions = 16777216; // 2**24

  // uncomment when the data structure is written
  // let pendingPool = OrderedPool<TransactionRequest>(max_size);

  /*
  Pending transactions are also saved to a lookup datastructure by submit number. Initially we use a TrieMap.
  */

  let pendingLookup = TrieMap.TrieMap<SubmitNumber, TransactionRequest>(Nat.equal, Nat32.fromNat);

  // update functions

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
 
  // query functions

  type TransactionError = { #NotFound; };
  public query func txDetails(transferId: TransactionId): async Result<TransactionRequest, TransactionError> {
    nyi();
  };

  // admin interface

  // set own aggregator id
  public func set_id(id : Nat) {
    nyi();
  };
};
