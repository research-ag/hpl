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
  public type Transaction = T.Transaction;
  type TransactionId = T.TransactionId;
 
  // canister id of the ledger canister
  let ledger : Principal = _ledger; 
 
  // the own unique identifier of this aggregator
  let selfAggregatorIndex: Nat = own_id;

  /*
  The aggregator sends the transactions in batches to the ledger. It does so at every invocation by the heartbeat functionality.
  Between heartbeats, approved transaction queue up and get stored in a queue. The batches have a size limit. At every heartbeat, 
  we pop as many approved transactions from the queue as fit into a batch and send the batch.

  In a future iteration we can send more than one batch per heartbeat. But such an approach requires a mechanism to slow down when 
  delivery failures occur. We currently do not implement it. 

  The queue is of type Deque<Transaction>. 
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

  // This is the transaction request that can be queried by submit_number
  type TransactionRequest = {
    transaction : Transaction;
    submitter : Principal;
    submit_number : SubmitNumber;
    status : { #pending : Approvals; #approved : QueueNumber; #rejected : Bool  };
  };

  // This is how we internally store a transaction request.
  type TransactionRequestInternal = {
    transaction : Transaction;
    submitter : Principal;
    submit_number : SubmitNumber;
    status : { #pending : Approvals; #approved : QueueNumber; #rejected : Bool  };
    pool : Nat; 
    prev_pending : SubmitNumber;  
    next_pending : SubmitNumber;
  };

  /*
  Transaction requests are assigned to "pools". In the initial implementation there is only one global pool.
  In the future there can be multiple pools and submitters can reserve their own pool with a chosen capacity for a fee.
 
  A pool has a fixed capacity. A pool tracks how many transaction requests it contains (var total), how many of them are 
  pending (var pending), and how many are queued (total-pending).

  The pending transaction requests in a pool form one chain that reflects their order of submission. The Pool stores the head and 
  tail of that chain (first and last) and each TransactionRequest stores its neighbours in the chain (prev and next).
  
  When a transaction first becomes fully approved then it is removed from the chain by manipulating the neighbours' prev 
  and next values and, possibly, the pool's first and last value. Moreover the pending value in the pool is decremented.

  When a transaction request is popped from the queue then the queued value of its pool is decremented.

  When a new transaction request is made then the following happens:
    1. If queued == capacity then we don't have space for this request. We cannot delete queued requests. 
    2. If total == capacity (but queued < capacity) then pending must be > 0. Then we delete the first (=oldest) pending transaction.
       To do this we first look up the transaction request under the submit number first_pending. 
       Then we remove that transaction request from the lookup data structure. 
       Then we remove it from the chain of pending transactions by setting the pool's value first_pending to the request's value of next_pending. 
    3. Then we add the new transaction to the lookup data structure and set the pool's value last_pending. 
  */

  type Pool = {
    capacity : Nat;
    var first_pending : ?SubmitNumber;
    var last_pending : ?SubmitNumber;
    var pending : Nat;
    var total : Nat;
  };
  
  let pool : Pool = { 
    capacity = 16777216;
    var first_pending = null;
    var last_pending = null;
    var pending = 0;
    var total = 0 
  };
  
  // If 256 new transactions are submitted per second and never approved then in a pool of size 2**24 they last for ~18h before they get overwritten. 
  let max_transactions = 16777216; // 2**24

  /*
  Pending transactions are also saved to a lookup datastructure by submit number. Initially we use a TrieMap.
  They stay in the lookup data structure when they move from the pool to the queue.
  They are removed from the lookup data structure when they are popped from the queue and batched.
  Thus, the number of entries in the lookup data structures equals the value total of the pool. Or the sum of all values total if there are multiple pools.
  */

  let lookup = TrieMap.TrieMap<SubmitNumber, TransactionRequest>(Nat.equal, Nat32.fromNat);

  /*
  When a TransactionRequest is popped from the queue and batched then it is also removed from the pool it belongs to and from the lookup data structure.
  */

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
