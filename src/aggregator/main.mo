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
  public type Tx = T.Tx;
  type LocalTxId = T.LocalTxId;
  type GlobalTxId = T.GlobalTxId;
 
  // canister id of the ledger canister
  let ledger : Principal = _ledger; 
 
  // the own unique identifier of this aggregator
  let selfAggregatorIndex: Nat = own_id;

  /* 
  Glossary:
  transaction : The information that is being sent to the ledger if the transaction is approved. It captures a) everything needed during ledger-side validation of the transaction and b) everything needed to define the effect on the ledger if executed.

  transaction request: The information of a transaction plus transient information needed while the transaction lives in the aggregator. 

  local tx id : An id that uniquely identifies a transaction request inside this aggregator. It is issued when a transaction request is first submitted. It is never re-used again for any other request regardless of whether the transaction request is approved, rejected or otherwise deleted (expired). It stays with the transaction if the transaction is send to the ledger. 

  global tx is : The local id plus aggregator id makes a globally unique id. 
 
  fully approved: A tx request that is approved by all contributors that are not marked as auto_approve by the tx. A fully approved tx is queued.

  pending tx : A tx request that is not yet fully approved.
  */

  /* 
  Lifetime of a transaction request:
  - transaction (short: tx) submitted by the user becomes a transaction request
  - pre-validation: is it too large? too many fields, etc.?
  - tx is added to the lookup table. if there is no space then it is rejected, if there is space then the lookup table
    - generates a unique local tx id
    - stores the local tx id in the tx in the request
    - stores the tx request
    - returns the local tx id  
  - global tx id is returned to the user
  - when approve and reject is called then the tx is looked up by its local id
  - when a tx is fully approved its local id is added to the queue
  - value of counter `batch_number` is stored inside the tx request and the counter incremented
  - when a tx is popped from the queue (batched) then
    - the tx is deleted from the lookup table 
    - the counter `batched` is incremented

  The lookup table internally maintains three values:
  - capacity (constant) = the total number of slots available in the lookup table, used and unused
  - used = the number of slots used (equals the number of pending txs plus queued txs)
  - pending = the number of pending txs  

  debug counters:
  - submitted : counts all that are ever submitted
  */

  /*
  The aggregator sends the transactions in batches to the ledger. It does so at every invocation by the heartbeat functionality.
  Between heartbeats, approved transaction queue up and get stored in a queue. The batches have a size limit. At every heartbeat, 
  we pop as many approved transactions from the queue as fit into a batch and send the batch.

  In a future iteration we can send more than one batch per heartbeat. But such an approach requires a mechanism to slow down when 
  delivery failures occur. We currently do not implement it. 

  The queue is of type Deque<Tx>. We don't need a double-ended queue but this is the only type of queue available in motoko-base.
  Deque is a functional data structure, hence it is a mutable variable.
  */

  var approvedTxs = Deque.empty<Tx>();

  // global counters 
  var batch_number : Nat = 0;
  var batched : Nat = 0;

  // debug counter 
  var submitted : Nat = 0;

  /* 
  Here is the information that makes up a transaction request.
  `Approvals` is a vector that captures the information who has already approved the transaction.
  The vector's length equals the number of contributors to the transactions.
  When a tx is approved (i.e. queued) then it has a batch number and the batch number is stored in the #approved field in the status variant.
  */

  type Approvals = [Bool];
  type TxRequest = {
    transaction : Tx;
    submitter : Principal;
    local_id : LocalTxId;
    status : { #pending : Approvals; #approved : Nat; #rejected : Bool  };
  };

  /*
  The lookup table.
  */

  let lookup = object {
    let capacity = 16777216; // number of slots available in the table
   
    var unused : Nat =  16777216; // number of unused slots
    var unmarked : Nat = 0; // individual used slots can be "marked", this is the number of used, unmarked slots
 
    // add an element to the table
    // if the table is not full then take an usued slot (the slot will start as unmarked)
    // if the table is full but there are unmarked slots then overwrite the oldest slot that is unmarked
    // if the table is full and all slots are marked then abort
    public func add(txreq : TxRequest) : ?LocalTxId { nyi() }; 

    // look up an element by id and return it 
    // abort if the id cannot be found 
    public func get(lid : LocalTxId) : ?TxRequest { nyi() }; 
 
    // look up an element by id and mark its slot 
    // abort if the id cannot be found 
    public func mark(lid : LocalTxId) : ?TxRequest { nyi() }; 

    // look up an element by id and empty its slot
    // ignore if the id cannot be found 
    public func remove(lid : LocalTxId) : () { nyi() };
  };

  /*
  The function `mark` will be called when a tx becomes fully approved. The reason is that we want to be able to overwrite old pending 
  transactions like in a circular buffer, but we never want to overwrite transactions that are already queued.

  The lookup table is going to be implemented as an array of size `capacity` and element type `Slot` (see below). 

  If 256 new transactions are submitted per second and never approved then, in a table of size 2**24, they last for ~18h before their slot gets overwritten. 

  The elements in the array are called "slots" are numbered 0,..,capacity-1.
  */
 
  type Slot = {
    var value : ?TxRequest; // value `none` means the slot is empty
    var counter : Nat; // must be initialized to 0
    var next_index : ?Nat; // this must be initialized dynamically to i+1 for slot i and null for slot capacity-1
    var prev_index : ?Nat; // this must be initialized dynamically to i-1 for slot i and null for slot 0 
  };

  /* 
  Given a first index into the table and following recursively the `next_index` one gets a chain of slots inside the table.
  The chain ends when the `next_index` value is `none`.

  The following type captures such a chain. The value is either the empty chain or the chain with the two ends given by the 
  two Nats which refer to the index of the first and the last slot in the chain.
  */  

  type Chain = { #empty; #ends : (Nat, Nat) };

  /* 
  The following variables are listed as global variables here below but will become part of the lookup object:
  */

  var unused_chain : Chain = #ends(0, 16777215);
  var unmarked_chain : Chain = #empty;

  /*
  Chains are used like queues, i.e. elements are removed from the head (first element) and added at the tail (last element), 
  but we can also remove elements from somewhere in the middle.

  If a new element is added and the unused chain is non-empty then:
    - the first slot is popped from the unused_chain
    - for this slot:
      - the new element is stored in the `value` field of the slot
      - the local id to be returned is composed of the index of the slot and the `counter` field of the slot, e.g.:
          local_id := counter*2**16 + slot_index
      - the `counter` field of the slot is incremented
      - the slot is pushed to the unmarked_chain

  If a new element is added, the unused chain is empty and the unmarked chain is non-empty then:
    - the first slot is popped from the unmarked_chain and used as above to
      - store the element
      - build local id
      - increment `counter` value

  When a lookup happens then the local id is first decomposed to obtain the slot id, e.g.
    slot_index := local_id % 2**24;
    counter_value := local_id / 2**24;
  If the `counter` value in slot `slot_index` does not equal `counter_value` then it means the local id entry is no longer stored (has been overwritten) and the lookup failed. 
  If it equals and the `value` field in the slot is `none` then it means the local id entry is no longer stored (removed) and the lookup failed.  
  Otherwise the lookup was successful.

  If a used slot gets marked then it is removed from the unmarked_chain.
 
  If the element in a used slot is removed then:
    - the value in the slot is set to `none`
    - the slot is pushed to the unused_chain. 

  So the theoretical transitions of a slot are: 
    unused_chain ->(add) unmarked_chain ->(remove) unused_chain
    unused_chain ->(add) unmarked_chain ->(mark) not in any chain ->(remove) unused_chain

  In practice what happens is:
    unused_chain ->(tx is added) unmarked_chain ->(tx gets fully approved) not in any chain ->(tx gets batched) unused_chain 
  */

  // update functions

  type SubmitError = { #NoSpace; #Invalid; };
  public func submit(transfer: Tx): async Result<GlobalTxId, SubmitError> {
    nyi();
  };

  type NotPendingError = { #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public func approve(transferId: GlobalTxId): async Result<(),NotPendingError> {
    nyi();
  };

  public func reject(transferId: GlobalTxId): async Result<(),NotPendingError> {
    nyi();
  };
 
  // query functions

  type TxError = { #NotFound; };
  public query func txDetails(transferId: GlobalTxId): async Result<TxRequest, TxError> {
    nyi();
  };

  // admin interface

  // set own aggregator id
  public func set_id(id : Nat) {
    nyi();
  };
};
