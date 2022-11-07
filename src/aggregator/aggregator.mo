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
import Tx "../shared/transaction";
import u "../shared/utils";
import SlotTable "../shared/slot_table";
import HPLQueue "../shared/queue";
import DLL "../shared/dll";

module {

  // type import work-around
  public type Result<X,Y> = R.Result<X,Y>;
  public type LocalId = T.LocalId;
  public type GlobalId = T.GlobalId;
  public type AggregatorId = T.AggregatorId;

  public type Batch = Tx.Batch;
  public type AssetId = Tx.AssetId;

  public type SubmitError = Tx.ValidationError or { #NoSpace; };
  public type NotPendingError = { #WrongAggregator; #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public type TxError = { #NotFound; };

  /*
  Here is the information that makes up a transaction request (txreq).
  `Approvals` is a vector that captures the information who has already approved the transaction.
  The vector's length equals the number of contributors to the transactions.
  When a txreq is fully approved then it is queued for being sent to the ledger and its status changes to #approved.
  The `push_ctr` value of the queue is stored in the #approved variant.
  */
  public type MutableApprovals = [var Bool];
  public type Approvals = [Bool];
  public type TxReq = {
    tx : Tx.Tx;
    submitter : Principal;
    var lid : ?LocalId;
    var status : { #unapproved : MutableApprovals; #approved : Nat; #rejected; #pending; #failed_to_send };
    size: Nat;
  };

  /*
  Here is the information we return to the user when the user queries for tx details.
  The difference to the internally stored TxReq is:
  - global id instead of local id
  - the Nat in variant #approved is not the same. Here, we subtract the value `pop_ctr` to return the queue position.
  */
  public type TxDetails = {
    tx : Tx.Tx;
    submitter : Principal;
    gid : GlobalId;
    status : { #unapproved : Approvals; #approved : Nat; #rejected; #pending; #failed_to_send };
  };

  public class Aggregator(ledger : Principal, ownId : AggregatorId, lookupTableCapacity: Nat) {
    // define the ledger actor
    let Ledger_actor = actor (Principal.toText(ledger)) : LedgerAPI.LedgerAPI;

    /*
    Glossary:
    transaction (short: tx): The information that is being sent to the ledger if the transaction is approved. It captures a) everything needed during ledger-side validation of the transaction and b) everything needed to define the effect on the ledger if executed.

    transaction request (short: tx request): The information of a transaction plus transient information needed while the transaction lives in the aggregator.

    local tx id (short: local id): An id that uniquely identifies a transaction request inside this aggregator. It is issued when a transaction request is first submitted. It is never re-used again for any other request regardless of whether the transaction request is approved, rejected or otherwise deleted (expired). It stays with the transaction if the transaction is send to the ledger.

    global tx id (short: global id): The local id plus aggregator id makes a globally unique id.

    fully approved: A tx request that is approved by all contributors. A fully approved tx is queued.

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

    // global counters
    let ctr = {
      var submitted : Nat = 0 // number of tx requests ever submitted
    };

    // lookup table
    var lookup : SlotTable.SlotTable<DLL.Cell<TxReq>> = SlotTable.SlotTable<DLL.Cell<TxReq>>(lookupTableCapacity);
    // chain of all used slots with an unapproved tx request
    var unapproved : DLL.DoublyLinkedList<TxReq> = DLL.DoublyLinkedList<TxReq>();
    // the queue of approved requests for batching
    var approvedTxs = HPLQueue.HPLQueue<LocalId>();

    // Create a new transaction request.
    // Here we init it and put to the lookup table.
    // If the lookup table is full, we try to reuse the slot with oldest unapproved request
    public func submit(caller: Principal, tx: Tx.Tx): Result<GlobalId, SubmitError> {
      switch (Tx.validate(tx, true)) {
        case (#err error) { return #err(error) };
        case (_) {}
      };
      let txSize = Tx.size(tx);
      ctr.submitted += 1;
      let approvals: MutableApprovals = Array.tabulateVar(tx.map.size(), func (i: Nat): Bool = tx.map[i].owner == caller or (tx.map[i].outflow.size() == 0 and tx.map[i].mints.size() == 0 and tx.map[i].burns.size() == 0));
      let txRequest : TxReq = {
        tx = tx;
        submitter = caller;
        var lid = null;
        var status = #unapproved(approvals);
        size = txSize;
      };
      let cell = unapproved.pushBack(txRequest);
      txRequest.lid := lookup.add(cell);
      switch (txRequest.lid) {
        case (?lid) {
          checkIsApprovedAndEnqueue(txRequest, lid, Array.freeze(approvals));
          #ok(ownId, lid);
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
                  #ok(ownId, lid);
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
      // if the batch is empty then stop
      // we don't send an empty batch
      if (requestsToSend.size() == 0) {
        return
      };
      try {
        await Ledger_actor.processBatch(Array.map(requestsToSend, func (req: TxReq): Tx.Tx = req.tx));
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

    let batchIter = object {
      var remainingRequests = 0;
      var remainingBytes = 0;
      public func reset() : () {
        remainingRequests := C.maxBatchRequests;
        remainingBytes := C.maxBatchBytes;
      };
      public func next() : ?TxReq {
        // number of requests is limited to `batchSize`
        // if reached then stop iteratortion
        if (remainingRequests == 0) { 
          return null 
        };
        // get the local id at the head of the queue
        switch (approvedTxs.peek()) {
          case (?lid) {
            // get the txreq from the lookup table 
            switch (lookup.get(lid)) {
              case (?cell) {
                let txreq = cell.value;
                // check if enough space for the txreq
                let bytesNeeded = txreq.size + 1;
                if (remainingBytes < bytesNeeded) {  
                  return null // stop iteration
                } else { 
                  // pop local id from queue and return the txreq
                  ignore approvedTxs.dequeue(); 
                  remainingBytes -= bytesNeeded;
                  remainingRequests -= 1;
                  txreq.status := #pending;
                  return ?txreq 
                }
              };
              case (null) {
                // txreq must have been overwritten in the lookup table
                // should never happen: trap
                assert false 
              }
            };
          };
          case _ {} // queue was empty: stop iteration
        };
        return null;
      };
    };

    public func getNextBatchRequests(): [TxReq] {
      batchIter.reset();
      Iter.toArray(batchIter)
    };

    // private functionality
    /** get info about pending request. Returns user-friendly errors */
    private func getPendingTxRequest(txId: GlobalId, caller: Principal): Result<( txRequest: TxReq, approvals: MutableApprovals, index: Nat ),NotPendingError> {
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
              switch (u.arrayFindIndex(tr.tx.map, func (c: Tx.Contribution) : Bool { c.owner == caller })) {
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
    private func cleanupOldest(chain: DLL.DoublyLinkedList<TxReq>) : Bool {
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
    private func checkIsApprovedAndEnqueue(tr: TxReq, lid: LocalId, approvals: Approvals) {
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
