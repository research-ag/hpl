import { nyi; xxx } "mo:base/Prelude";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Ledger "../ledger/main";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Bool "mo:base/Bool";
import R "mo:base/Result";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import v "../shared/validators";
import u "../shared/utils";
import SlotTable "../shared/slot_table";
import HPLQueue "../shared/queue"

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
  */

  var approvedTxs = HPLQueue.HPLQueue<LocalId>();

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

  type MutableApprovals = [var Bool];
  type Approvals = [Bool];
  type TxRequest = {
    tx : Tx;
    submitter : Principal;
    var lid : ?LocalId;
    var status : { #unapproved : MutableApprovals; #approved : Nat; #rejected; #pending; #failed_to_send };
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
    status : { #unapproved : Approvals; #approved : Nat; #rejected; #pending; #failed_to_send };
  };

  var lookup : SlotTable.SlotTable<TxRequest> = SlotTable.SlotTable<TxRequest>();

  // update functions

  type SubmitError = { #NoSpace; #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted };
  public shared(msg) func submit(tx: Tx): async Result<GlobalId, SubmitError> {
    let validationResult = v.validateTx(tx);
    switch (validationResult) {
      case (#err error) return #err(error);
      case (#ok) {};
    };
    let txRequest : TxRequest = {
      tx = tx;
      submitter = msg.caller;
      var lid = null;
      var status = #unapproved(Array.init(tx.map.size(), false));
    };
    txRequest.lid := lookup.add(txRequest);
    switch (txRequest.lid) {
      case (null) #err(#NoSpace);
      case (?lid) #ok(selfAggregatorIndex, lid);
    };
  };

  type NotPendingError = { #WrongAggregator; #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public shared(msg) func approve(txId: GlobalId): async Result<(),NotPendingError> {
    let pendingRequestInfo = getPendingTxRequest(txId, msg.caller);
    switch (pendingRequestInfo) {
      case (#err err) return #err(err);
      case (#ok (tr, approvals, index)) {
        approvals[index] := true;
        if (Array.foldRight(Array.freeze(approvals), true, Bool.logand)) {
          let lid = txId.1;
          let pendingRequestInfo = lookup.mark(lid);
          approvedTxs.enqueue(lid);
          tr.status := #approved(approvedTxs.pushesAmount());
        };
        return #ok;
      };
    };
  };

  public shared(msg) func reject(txId: GlobalId): async Result<(),NotPendingError> {
    let pendingRequestInfo = getPendingTxRequest(txId, msg.caller);
    switch (pendingRequestInfo) {
      case (#err err) return #err(err);
      case (#ok (tr, _, _)) {
        tr.status := #rejected;
        lookup.remove(txId.1);
        return #ok;
      };
    };
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

  // private functionality

  private func getPendingTxRequest(txId: GlobalId, caller: Principal): Result<( txRequest: TxRequest, approvals: MutableApprovals, index: Nat ),NotPendingError> {
    let (aggregator, local_id) = txId;
    if (aggregator != own_id) {
      return #err(#WrongAggregator);
    };
    let txRequest = lookup.get(local_id);
    switch (txRequest) {
      case (null) return #err(#NotFound);
      case (?tr) {
        switch (tr.status) {
          case (#approved _)            return #err(#AlreadyApproved);
          case (#pending)               return #err(#AlreadyApproved);
          case (#failed_to_send)        return #err(#AlreadyApproved);
          case (#rejected)              return #err(#AlreadyRejected);
          case (#unapproved approvals)  {
            switch (u.arrayFindIndex(tr.tx.map, func (c: T.Contribution) : Bool { c.owner == caller })) {
              case (#NotFound) return #err(#NoPart);
              case (#Found index) {
                return #ok( tr, approvals, index );
              };
            };
          };
        };
      };
    };
    return #err(#NotFound);
  };

};
