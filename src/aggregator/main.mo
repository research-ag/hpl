import { nyi; xxx } "mo:base/Prelude";
import Deque "mo:base/Deque";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Ledger "../ledger/main";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";

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
actor class Aggregator(_ledger : Principal, own_id : T.AggregatorId) {

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  public type Tx = T.Tx;
  type LocalId = T.LocalId;
  type GlobalId = T.GlobalId;
  type Batch = T.Batch;
  type AggregatorId = T.AggregatorId;
  type AssetId = T.AssetId;

  /* store the init arguments: 
       - canister id of the ledger canister
       - own unique identifier of this aggregator
  */
  let ledger : Principal = _ledger; 
  let selfAggregatorIndex: AggregatorId = own_id;

  // define the ledger actor
  let Ledger_actor = actor (Principal.toText(ledger)) : Ledger.Ledger;

  /* 
  Glossary:
  transaction (short: tx): The information that is being sent to the ledger if the transaction is approved. It captures a) everything needed during ledger-side validation of the transaction and b) everything needed to define the effect on the ledger if executed.

  transaction request (short: tx request): The information of a transaction plus transient information needed while the transaction lives in the aggregator. 

  local tx id (short: local id): An id that uniquely identifies a transaction request inside this aggregator. It is issued when a transaction request is first submitted. It is never re-used again for any other request regardless of whether the transaction request is approved, rejected or otherwise deleted (expired). It stays with the transaction if the transaction is send to the ledger. 

  global tx id (short: global id): The local id plus aggregator id makes a globally unique id. 
 
  fully approved: A tx request that is approved by all contributors that are not marked as auto_approve by the tx. A fully approved tx is queued.

  unapproved: A tx request that is not yet fully approved.
  */

  /* 
  Lifetime of a transaction request:
  - tx submitted by the user becomes a transaction request
  - pre-validation: is it too large? too many fields, etc.?
  - tx is added to the lookup table. if there is no space then it is rejected, if there is space then the lookup table
    - generates a unique local tx id
    - stores the local tx id in the tx in the request
    - stores the tx request
    - returns the local tx id  
  - global tx id is returned to the user
  - when approve and reject is called then the tx is looked up by its local id
  - when a tx is fully approved its local id is queued for batching
  - value of `push_ctr` is stored inside the tx request and `push_ctr` incremented
  - when a local tx id is popped from the queue then
    - the tx is deleted from the lookup table 
    - `pop_ctr` is incremented

  The lookup table internally maintains three values:
  - capacity (constant) = the total number of slots available in the lookup table, i.e. used slots plus unused slots
  - used = the number of used slots (equals the number of unapproved txs plus queued txs)
  - unapproved = the number of unapproved txs  

  debug counters:
  - submitted : counts all that are ever submitted
  */

  /*
  The aggregator sends the transactions in batches to the ledger. It does so at every invocation by the heartbeat functionality.
  Between heartbeats, approved transaction queue up and get stored in a queue. The batches have a size limit. At every heartbeat, 
  we pop as many approved transactions from the queue as fit into a batch and send the batch.

  In a future iteration we can send more than one batch per heartbeat. But such an approach requires a mechanism to slow down when 
  delivery failures occur. We currently do not implement it. 

  The queue is of type Deque<LocalId>. We don't need a double-ended queue but this is the only type of queue available in motoko-base.
  Deque is a functional data structure, hence it is a mutable variable.
  */

  var approvedTxs = Deque.empty<LocalId>();

  /*
  global counters 
  push_ctr = number of txs that were ever pushed to the queue
  pop_ctr = number txs that were ever popped from the queue
  the difference between the two equals the current length of the queue 
  */
  var push_ctr : Nat = 0;
  var pop_ctr : Nat = 0;

  /* 
  debug counter
  number of tx requests ever submitted 
  */
  var submitted : Nat = 0;

  /* 
  Here is the information that makes up a transaction request.
  `Approvals` is a vector that captures the information who has already approved the transaction.
  The vector's length equals the number of contributors to the transactions.
  When a tx is approved (i.e. queued) then the value `push_ctr` is stored in the #approved field in the status variant.
  */

  type Approvals = [Bool];
  type TxRequest = {
    tx : Tx;
    submitter : Principal;
    lid : LocalId;
    status : { #unapproved : Approvals; #approved : Nat; #rejected; #pending; #failed_to_send };
  };
 
  /* 
  Here is the information we return to the user when the user queries for tx details.
  The difference to the internally stored TxRequest is:
  - global id instead of local id
  - the Nat in variant #approved is not the same. Here, we subtract the value `pop_ctr` to return the queue position.
  */

  type TxDetails = {
    tx : Tx;
    submitter : Principal;
    gid : GlobalId;
    status : { #unapproved : Approvals; #approved : Nat; #rejected; #pending };
  };
 
  /*
  Our lookup data structure has the following interface.

  The function `mark` will be called when a tx becomes fully approved. The reason is that we want to be able to overwrite old unapproved 
  transactions like in a circular buffer, but we never want to overwrite transactions that are already queued.
  */

  type Lookup = {
    // calculate local id for provided transaction request
    // does not affect table itself and does not check if slot available
    getLocalId : (tx: Tx, caller: Principal) -> (LocalId) ; 

    // add an element to the data structure  
    // return null if there is no space, otherwise assign a new local id to the element and return the id
    // the data structure is allowed to overwrite the oldest unmarked element
    add : (txreq : TxRequest) -> (?LocalId) ; 

    // look up an element by id and return it 
    // return null if the id cannot be found 
    get : (lid : LocalId) -> (?TxRequest) ; 
 
    // look up an element by id and mark it so it cannot be overwritten 
    // return null if the id cannot be found 
    mark : (lid : LocalId) -> (?TxRequest) ; 

    // look up an element by id and delete it
    // ignore if the id cannot be found 
    remove : (lid : LocalId) -> () ;
  };

  /*
  We implement our lookup data structure as a lookup table (array) with a fixed number of slots.
  The slots are numbered 0,..,N-1.

  If 256 new transactions are submitted per second and never approved then, in a table with N=2**24 slots, they stay for ~18h before their slot gets overwritten. 

  Each slot is an element of the following type:
    value : stored the tx request if the slot is currently used
    counter : counts how many times the slot has already been used (a trick to generate a unique local id)
    next/prev_index : used to track the order in which slots are to be used
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

  The following type captures such a chain.

  Chains are used like queues, i.e. elements are removed from the head (first element) and added at the tail (last element), 
  but we can also remove elements from somewhere in the middle.
  */  

  type Chain = { var length : Nat; var head : ?Nat; var tail : ?Nat };

  /* 
  Our lookup table is the following object.
  The `unused` chain contains all unused slot indices and defines the order in which they are filled with new tx requests.
  The `unapproved` chain contains all used slot indices that contain a unapproved tx request and defines the order in which they are to be overwritten.

  We currently utilize only one unapproved chain. In the future there can be multiple chains. A principal can buy its own chain of a certain capacity for a fee.
  Then the principal's own requests cannot be overwritten by others. But there is an recurring fee to reserve the chain capacity.
  */

  let lookup : Lookup = object {
    let capacity = 16777216; // number of slots available in the table

    // see below for explanation of the Slot type  
    let slots : [Slot] = Array.tabulate<Slot>(16777216, func(n : Nat) { switch (n) {
      case (0) { let s : Slot = { var value = null; var counter = 0; var next_index = ?(n+1); var prev_index = null} };
      case (16777215) { let s : Slot = { var value = null; var counter = 0; var next_index = null; var prev_index = ?(n-1)} };
      case (_) { let s : Slot = { var value = null; var counter = 0; var next_index = ?(n+1); var prev_index = ?(n-1)} };
    }});

    // see below for explanation of the Chain type  
    let unused : Chain = { var length = 16777216; var head = ?0; var tail = ?16777215 }; // chain of all unused slots 
    let unapproved : Chain = { var length = 0; var head = null; var tail = null }; // chain of all used slots with a unapproved tx request

    // calculate local id for provided transaction request
    // does not affect table itself and does not check if slot available
    public func getLocalId(tx: Tx, caller: Principal) : LocalId { 
      nyi();
    }; 
 
    // add an element to the table
    // if the table is not full then take an usued slot (the slot will shift to unapproved)
    // if the table is full but there are unapproved slots then overwrite the oldest unapproved slot
    // if the table is full and there are no unapproved slots then abort
    public func add(txreq : TxRequest) : ?LocalId { 
      let localId = getLocalId(txreq.tx, txreq.submitter);
      nyi()
    }; 

    // look up an element by id and return it 
    // abort if the id cannot be found 
    public func get(lid : LocalId) : ?TxRequest { nyi() }; 
 
    // look up an element by id and mark its slot 
    // abort if the id cannot be found 
    public func mark(lid : LocalId) : ?TxRequest { nyi() }; 

    // look up an element by id and empty its slot
    // ignore if the id cannot be found 
    public func remove(lid : LocalId) : () { nyi() };
  };

  /*
  Further details about the implementation of the functions:

  If a new element is added and the unused chain is non-empty then:
    - the first slot is popped from the `unused` chain
    - for this slot:
      - the new element is stored in the `value` field of the slot
      - the local id to be returned is composed of the index of the slot and the `counter` field of the slot, e.g.:
          lid := counter*2**16 + slot_index
      - the `counter` field of the slot is incremented
      - the slot is pushed to the `unapproved` chain

  If a new element is added, the unused chain is empty and the unapproved chain is non-empty then:
    - the first slot is popped from the `unapproved` chain and used as above to
      - store the element
      - build local id
      - increment `counter` value

  When a lookup happens then the local id is first decomposed to obtain the slot id, e.g.
    slot_index := lid % 2**24;
    counter_value := lid / 2**24;
  If the `counter` value in slot `slot_index` does not equal `counter_value` then it means the local id entry is no longer stored (has been overwritten) and the lookup failed. 
  If it equals and the `value` field in the slot is `none` then it means the local id entry is no longer stored (removed) and the lookup failed.  
  Otherwise the lookup was successful.

  If a used slot gets marked (happens when the tx request gets approved) then it is removed from the `unapproved` chain.
 
  If the element in a used slot is removed then:
    - the value in the slot is set to `none`
    - the slot is pushed to the `unused` chain. 

  So the theoretical transitions of a slot are: 
    unused ->(add) unapproved ->(remove) unused
    unused ->(add) unapproved ->(mark) not in any chain ->(remove) unused

  In practice what happens is:
    unused_chain ->(tx is added) unapproved ->(tx gets fully approved) not in any chain ->(tx gets batched) unused 
  */

  // update functions

  type SubmitError = { #NoSpace; #Invalid; };
  public shared(msg) func submit(transfer: Tx): async Result<GlobalId, SubmitError> {
    if (transfer.map.size() > T.max_contribution) {
      return #err(#Invalid);
    };
    for (contribution in transfer.map.vals()) {
      if (contribution.inflow.size() + contribution.outflow.size() > T.max_flows) {
        return #err(#Invalid);
      };
      switch (contribution.memo) {
        case (?m) {
          if (m.size() > T.max_memo_size) {
            return #err(#Invalid);
          };
        };
        case (null) {};
      };
      let assetBalanceMap: TrieMap.TrieMap<AssetId, Int> = TrieMap.TrieMap<AssetId, Int>(func (a : AssetId, b: AssetId) : Bool { a == b }, func (a : Nat) { Nat32.fromNat(a) });
      for (flows in [contribution.inflow, contribution.outflow].vals()) {
        let negate : Bool = flows == contribution.outflow;
        var lastSubaccountId : Nat = 0;
        for ((subaccountId, asset) in flows.vals()) {
          if (lastSubaccountId > 0 and subaccountId <= lastSubaccountId) {
            return #err(#Invalid);
          };
          lastSubaccountId := subaccountId;
          switch asset {
            case (#ft (id, quantity)) {
              let currentBalance : ?Int = assetBalanceMap.get(id);
              switch (currentBalance) {
                case (?b) { 
                  if (negate) {
                    assetBalanceMap.put(id, b - quantity);
                  } else {
                    assetBalanceMap.put(id, b + quantity);
                  };
                };
                case (null) { 
                  // out flows are being processed after in flows, so if we have out flow and did not have in flow, 
                  // it will never add up to zero
                  if (negate) {
                    return #err(#Invalid);
                  };
                  assetBalanceMap.put(id, quantity); 
                };
              };
            };
          };
        };
      };
      for (balance in assetBalanceMap.vals()) {
        if (balance != 0) {
          return #err(#Invalid);
        };
      };
    };
    let transactionRequest : TxRequest = {tx = transfer; submitter = msg.caller; lid = lookup.getLocalId(transfer, msg.caller); status = #unapproved([]) };
    let lid = lookup.add(transactionRequest);
    if (lid == null) {
      return #err(#NoSpace);
    };
    #ok (selfAggregatorIndex, transactionRequest.lid);
  };

  type NotPendingError = { #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public func approve(transferId: GlobalId): async Result<(),NotPendingError> {
    nyi();
  };

  public func reject(transferId: GlobalId): async Result<(),NotPendingError> {
    nyi();
  };
 
  // query functions

  type TxError = { #NotFound; };
  public query func txDetails(gid: GlobalId): async Result<TxDetails, TxError> {
    nyi();
  };

  // heartbeat function

  system func heartbeat() : async () {
    let b : Batch = []; // pop from queue here
    try {
      await Ledger_actor.processBatch(b);
      // the batch has been processed
      // the transactions in b are now explicitly deleted from the lookup table
      // the aggregator has now done its job
      // the user has to query the ledger to see the execution status (executed or failed) and the order relative to other transactions 
    } catch (e) {
      // batch was not processed
      // we do not retry sending the batch
      // we set the status of all txs to #failed_to_send
      // we leave all txs in the lookup table forever
      // in the lookup table all of status #approved, #pending, #failed_to_send remain outside any chain, hence they won't be deleted
      // only an upgrade can clean them up 
    };
  };

};
