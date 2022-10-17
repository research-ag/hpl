import Array "mo:base/Array";
import Principal "mo:base/Principal";
import LedgerAPI "../ledger/ledger_api";
import Bool "mo:base/Bool";
import R "mo:base/Result";
import Iter "mo:base/Iter";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import C "../shared/constants";
import v "../shared/validators";
import u "../shared/utils";
import SlotTable "../shared/slot_table";
import HPLQueue "../shared/queue";
import DLL "../shared/dll";

module {

  // type import work-around
  public type Result<X,Y> = R.Result<X,Y>;
  public type Tx = T.Tx;
  public type LocalId = T.LocalId;
  public type GlobalId = T.GlobalId;
  public type Batch = T.Batch;
  public type AggregatorId = T.AggregatorId;
  public type AssetId = T.AssetId;

  public type SubmitError = v.TxValidationError or { #NoSpace; };
  public type NotPendingError = { #WrongAggregator; #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public type TxError = { #NotFound; };

  /*
  Here is the information that makes up a transaction request.
  `Approvals` is a vector that captures the information who has already approved the transaction.
  The vector's length equals the number of contributors to the transactions.
  When a tx is approved (i.e. queued) then the value `push_ctr` is stored in the #approved field in the status variant.
  */
  public type MutableApprovals = [var Bool];
  public type Approvals = [Bool];
  public type TxRequest = {
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
  public type TxDetails = {
    tx : Tx;
    submitter : Principal;
    gid : GlobalId;
    status : { #unapproved : Approvals; #approved : Nat; #rejected; #pending; #failed_to_send };
  };

  public class Aggregator(ledger_ : Principal, ownId : T.AggregatorId, lookupTableCapacity: Nat) {
    /* store the init arguments:
        - canister id of the ledger canister
        - own unique identifier of this aggregator
    */
    let ledger : Principal = ledger_;
    let selfAggregatorIndex: AggregatorId = ownId;

    // define the ledger actor
    let Ledger_actor = actor (Principal.toText(ledger)) : LedgerAPI.LedgerAPI;

    /*
    Glossary:
    transaction (short: tx): The information that is being sent to the ledger if the transaction is approved. It captures a) everything needed during ledger-side validation of the transaction and b) everything needed to define the effect on the ledger if executed.

    transaction request (short: tx request): The information of a transaction plus transient information needed while the transaction lives in the aggregator.

    local tx id (short: local id): An id that uniquely identifies a transaction request inside this aggregator. It is issued when a transaction request is first submitted. It is never re-used again for any other request regardless of whether the transaction request is approved, rejected or otherwise deleted (expired). It stays with the transaction if the transaction is send to the ledger.

    global tx id (short: global id): The local id plus aggregator id makes a globally unique id.

    fully approved: A tx request that is approved by all contributors that are not marked as autoApprove by the tx. A fully approved tx is queued.

    unapproved: A tx request that is not yet fully approved.
    */

    /*
    Lifetime of a transaction request:
    - tx submitted by the user becomes a transaction request
    - pre-validation: is it too large? too many fields, etc.?
    - tx is being saved to unapproved list
    - tx cell in unapproved list is added to the lookup table. if there is no space then it is rejected, if there is space then the lookup table
      - generates a unique local tx id
      - stores the local tx id in the tx in the request
      - stores the cell with tx request
      - returns the local tx id
    - global tx id is returned to the user
    - when approve and reject is called then the tx is looked up by its local id
    - when a tx is fully approved its local id is queued for batching
    - when a local tx id is popped from the queue then the cell is deleted from the unapproved list and from the the lookup table. Slot becomes unused

    The aggregator sends the transactions in batches to the ledger. It does so at every invocation by the heartbeat functionality.
    Between heartbeats, approved transaction queue up and get stored in a queue. The batches have a size limit. At every heartbeat,
    we pop as many approved transactions from the queue as fit into a batch and send the batch.

    In a future iteration we can send more than one batch per heartbeat. But such an approach requires a mechanism to slow down when
    delivery failures occur. We currently do not implement it.
    */

    /*
    debug counter
    number of tx requests ever submitted
    */
    var submitted : Nat = 0;

    // lookup table
    var lookup : SlotTable.SlotTable<DLL.Cell<TxRequest>> = SlotTable.SlotTable<DLL.Cell<TxRequest>>(lookupTableCapacity);
    // chain of all used slots with a unapproved tx request
    var unapproved : DLL.DoublyLinkedList<TxRequest> = DLL.DoublyLinkedList<TxRequest>();
    // the queue of approved requests for batching
    var approvedTxs = HPLQueue.HPLQueue<LocalId>();

    /** Create a new transaction request.
    * Here we init it and put to the lookup table.
    * If the lookup table is full, we try to reuse the slot with oldest unapproved request
    */
    public func submit(caller: Principal, tx: Tx): Result<GlobalId, SubmitError> {
      let validationResult = v.validateTx(tx, true);
      switch (validationResult) {
        case (#err error) return #err(error);
        case (#ok) {};
      };
      let approvals: MutableApprovals = Array.tabulateVar(tx.map.size(), func (i: Nat): Bool = tx.map[i].autoApprove or tx.map[i].owner == caller);
      let txRequest : TxRequest = {
        tx = tx;
        submitter = caller;
        var lid = null;
        var status = #unapproved(approvals);
      };
      let cell = unapproved.pushBack(txRequest);
      txRequest.lid := lookup.add(cell);
      switch (txRequest.lid) {
        case (?lid) {
          checkIsApprovedAndEnqueue(txRequest, lid, Array.freeze(approvals));
          #ok(selfAggregatorIndex, lid);
        };
        case (null) {
          // try to reuse oldest unapproved
          if (unapproved.size() < 2) { // 1 means that chain contains only just added cell
            cell.removeFromList();
            return #err(#NoSpace);
          };
          let memoryFreed = cleanupOldest(unapproved);
          switch (memoryFreed) {
            case (false) {
              cell.removeFromList();
              #err(#NoSpace);
            };
            case (true) {
              txRequest.lid := lookup.add(cell);
              switch (txRequest.lid) {
                case (?lid) {
                  checkIsApprovedAndEnqueue(txRequest, lid, Array.freeze(approvals));
                  #ok(selfAggregatorIndex, lid);
                };
                case (null) {
                  cell.removeFromList();
                  #err(#NoSpace);
                }
              };
            };
          };
        };
      };
    };

    /** Approve request. If the caller made the last required approvement, it:
    * - marks request as approved
    * - removes transaction request from the unapproved list
    * - enqueues the request to the batch queue
    */
    public func approve(caller: Principal, txId: GlobalId): Result<(),NotPendingError> {
      let pendingRequestInfo = getPendingTxRequest(txId, caller);
      switch (pendingRequestInfo) {
        case (#err err) return #err(err);
        case (#ok (tr, approvals, index)) {
          approvals[index] := true;
          checkIsApprovedAndEnqueue(tr, txId.1, Array.freeze(approvals));
          return #ok;
        };
      };
    };

    /** Reject request. It marks request as rejected, but don't remove the request from unapproved list,
    * so it's status can still be queried until overwritten by newer requests
    */
    public func reject(caller: Principal, txId: GlobalId): Result<(),NotPendingError> {
      let pendingRequestInfo = getPendingTxRequest(txId, caller);
      switch (pendingRequestInfo) {
        case (#err err) return #err(err);
        case (#ok (tr, _, _)) {
          tr.status := #rejected;
          return #ok;
        };
      };
    };

    /** Query transaction request info */
    public func txDetails(gid: GlobalId): Result<TxDetails, TxError> {
      let txRequest = lookup.get(gid.1);
      switch (txRequest) {
        case (null) #err(#NotFound);
        case (?cell) {
          let txr = cell.value;
          return #ok({
            tx = txr.tx;
            submitter = txr.submitter;
            gid = gid;
            status = switch (txr.status) {
              case (#unapproved list) #unapproved(Array.freeze(list));
              case (#approved x) #approved(x);
              case (#rejected) #rejected();
              case (#pending) #pending();
              case (#failed_to_send) #failed_to_send();
            };
          });
        };
      };
    };

    /** heartbeat function */
    public func heartbeat() : async () {
      let requestsToSend = getNextBatchRequests();
      try {
        await Ledger_actor.processBatch(Array.map(requestsToSend, func (req: TxRequest): Tx = req.tx));
        // the batch has been processed
        // the transactions in b are now explicitly deleted from the lookup table
        // the aggregator has now done its job
        // the user has to query the ledger to see the execution status (executed or failed) and the order relative to other transactions
        for (req in requestsToSend.vals()) {
          switch (req.lid) {
            case (?l) lookup.remove(l);
            case (null) assert false; // should never happen
          };
        };
      } catch (e) {
        // batch was not processed
        // we do not retry sending the batch
        // we set the status of all txs to #failed_to_send
        // we leave all txs in the lookup table forever
        // in the lookup table all of status #approved, #pending, #failed_to_send remain outside any chain, hence they won't be deleted
        // only an upgrade can clean them up
        for (req in requestsToSend.vals()) {
          req.status := #failed_to_send;
        };
      };
    };

    public func getNextBatchRequests(): [TxRequest] =
      Iter.toArray(object {
        var counter = 0;
        public func next() : ?TxRequest {
          if (counter >= C.batchSize) {
            return null; // already added `batchSize` requests to the batch: stop iteration;
          };
          let lid = approvedTxs.dequeue();
          switch (lid) {
            case (null) {}; // queue ended: stop iteration;
            case (?l) {
              let cell = lookup.get(l);
              switch (cell) {
                case (null) assert false; // should never happen: request was overwritten in lookup table
                case (?c) {
                  counter += 1;
                  c.value.status := #pending;
                  return ?c.value;
                };
              };
            };
          };
          return null;
        };
      });

    // private functionality
    /** get info about pending request. Returns user-friendly errors */
    private func getPendingTxRequest(txId: GlobalId, caller: Principal): Result<( txRequest: TxRequest, approvals: MutableApprovals, index: Nat ),NotPendingError> {
      let (aggregator, local_id) = txId;
      if (aggregator != ownId) {
        return #err(#WrongAggregator);
      };
      let cell = lookup.get(local_id);
      switch (cell) {
        case (null) return #err(#NotFound);
        case (?c) {
          let tr = c.value;
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

    /** cleanup oldest unapproved request */
    private func cleanupOldest(chain: DLL.DoublyLinkedList<TxRequest>) : Bool {
      let oldestTrRequest = chain.popFront();
      switch (oldestTrRequest) {
        case (null) false;
        case (?req) {
          switch (req.lid) {
            case (?lid) {
              lookup.remove(lid);
              true;
            };
            // chain contained request without lid. Should never happen, but to be on the safe side let's try to cleanup further
            case (null) cleanupOldest(chain);
          };
        };
      };
    };

    /** check if transaction is fully approved and enqueue it to the batch */
    private func checkIsApprovedAndEnqueue(tr: TxRequest, lid: LocalId, approvals: Approvals) {
      if (Array.foldRight(approvals, true, Bool.logand)) {
        let cell = lookup.get(lid);
        // remove from unapproved list
        switch (cell) {
          case (?c) c.removeFromList();
          case (null) {};
        };
        approvedTxs.enqueue(lid);
        tr.status := #approved(approvedTxs.pushesAmount());
      };
    };

  };
};
