import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Array "mo:base/Array";
import { compare } "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";

import T "../shared/types";
import C "../shared/constants";
import v "../shared/validators";
import u "../shared/utils";
import CircularBuffer "../shared/circular_buffer";
// import LinkedListSet "../shared/linked_list_set";

module {

  public type Batch = T.Batch;
  public type Result<X,Y> = R.Result<X,Y>;
  public type AggregatorId = T.AggregatorId;
  public type SubaccountId = T.SubaccountId;
  public type Asset = T.Asset;

  public type SubaccountState = { asset: Asset; autoApprove: Bool };
  public type TxValidationError = v.TxValidationError;
  public type ProcessingError = TxValidationError or { #WrongOwnerId; #WrongSubaccountId; #InsufficientFunds; };
  public type BatchHistoryEntry = { batchNumber: Nat; precedingTotalTxAmount: Nat; results: [Result<(), ProcessingError>] };
  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  public type OwnerId = Nat;

  public class Ledger(initialAggregators : [Principal]) {


    // ================================ ACCESSORS =================================
    public func nAggregators(): Nat = aggregators.size();

    public func aggregatorPrincipal(aid: AggregatorId): Result<Principal, { #NotFound; }> =
      switch (aggregators.size() > aid) {
        case (true) #ok(aggregators[aid]);
        case (_) #err(#NotFound);
      };

    public func ownerId(p: Principal): Result<OwnerId, { #NotFound; }> =
      switch (owners.get(p)) {
        case (?oid) #ok(oid);
        case (_) #err(#NotFound);
      };

    public func nAccounts(p: Principal): Result<Nat, { #NotFound; }> =
      switch (ownerId(p)) {
        case (#ok oid) #ok(accounts[oid].size());
        case (#err err) #err(err);
      };

    public func asset(p: Principal, sid: SubaccountId): Result<SubaccountState, { #NotFound; #SubaccountNotFound; }> =
      switch (owners.get(p)) {
        case (null) #err(#NotFound);
        case (?oid)
          switch (accounts[oid].size() > sid) {
            case (true) #ok(accounts[oid][sid]);
            case (_) #err(#SubaccountNotFound);
          };
      };

    public func allAssets(owner : Principal) : Result<[SubaccountState], { #NotFound; }> =
      switch (owners.get(owner)) {
        case (null) #err(#NotFound);
        case (?oid) #ok(Array.freeze(accounts[oid]));
      };

    public func counters() : { totalBatches: Nat; batchesPerAggregator: [Nat]; totalTxs: Nat; failedTxs: Nat; succeededTxs: Nat } =
      {
        totalBatches = __totalBatchesProcessed;
        batchesPerAggregator = Array.freeze<Nat>(__batchesProcessedPerAggregator);
        totalTxs = __txsTotal;
        failedTxs = __txsFailed;
        succeededTxs = __txsSucceeded;
      };

    public func batchesHistory(startIndex: Nat, endIndex: Nat) : [BatchHistoryEntry] = batchHistory.slice(startIndex, endIndex);

    // ================================= MUTATORS =================================
    // add one aggregator principal
    public func addAggregator(p : Principal) : AggregatorId {
      // AG: Array.append is deprecated due to bad performance, however in this case it appears more optimal than converting to buffer
      aggregators := Array.append(aggregators, [p]);
      // for var arrays, even append does not exists...
      __batchesProcessedPerAggregator := Array.tabulateVar<Nat>(__batchesProcessedPerAggregator.size() + 1, func (i : Nat) : Nat {
        if (i < __batchesProcessedPerAggregator.size()) {
          __batchesProcessedPerAggregator[i];
        } else {
          0;
        };
      });
      aggregators.size() - 1;
    };

    public func registerOrSignPrincipal(p: Principal): Result<OwnerId, { #NoSpaceForPrincipal }> =
      switch (owners.get(p)) {
        case (?oid) #ok(oid);
        case (null) registerAccount(p);
      };

    public func openNewAccounts(p: Principal, n: Nat, autoApprove : Bool): Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount }> {
      switch (registerOrSignPrincipal(p)) {
        case (#err err) #err(err);
        case (#ok oid) {
          let oldSize = accounts[oid].size();
          if (oldSize + n > C.maxSubaccounts) {
            return #err(#NoSpaceForSubaccount);
          };
          // array.append seems to not work with var type
          accounts[oid] := Array.tabulateVar<SubaccountState>(oldSize + n, func (n: Nat) {
            if (n < oldSize) {
              return accounts[oid][n];
            };
            return { asset = #none; autoApprove = autoApprove };
          });
          #ok(oldSize);
        };
      };
    };

    private func registerAccount(principal: Principal) : Result<OwnerId, { #NoSpaceForPrincipal }> {
      let ownerId = ownersAmount;
      if (ownerId >= C.maxPrincipals) {
        return #err(#NoSpaceForPrincipal);
      };
      owners.put(principal, ownerId);
      ownersAmount += 1;
      accounts[ownerId] := Array.init<SubaccountState>(0, { asset = #none; autoApprove = false; });
      #ok(ownerId);
    };

    // ================================ PROCESSING ================================
    public func processBatch(aggregatorIndex: Nat, batch: Batch): () {
      let results: [var Result<(), ProcessingError>] = Array.init<Result<(), ProcessingError>>(batch.size(), #ok());
      label nextTx
      for (i in batch.keys()) {
        __txsTotal += 1;
        let tx = batch[i];

        // disabled validation, performed on the aggregator side. The ledger still validates:
        // - owner Id-s
        // - subaccount Id-s
        // - auto-approve flag
        // - asset type
        // - is balance sufficient

        // let validationResult = v.validateTx(tx, false);
        // if (R.isErr(validationResult)) {
        //     results[i] := validationResult;
        //     __txsFailed += 1;
        //     continue nextTx;
        // };

        // cache owner ids per contribution. If some owner ID is wrong - return error
        let ownersCache: [var OwnerId] = Array.init(tx.map.size(), 0);
        // checking uniqueness (disabled now, since aggregator alredy checked principal uniqueness)
        // let ownerIdsSet = LinkedListSet.LinkedListSet<Nat>(Nat.equal);
        for (j in ownersCache.keys()) {
          switch (owners.get(tx.map[j].owner)) {
            case (null) {
              results[i] := #err(#WrongOwnerId);
              __txsFailed += 1;
              continue nextTx;
            };
            case (?oid) {
              // if (not ownerIdsSet.put(oid)) {
              //   results[i] := #err(#OwnersNotUnique);
              //   __txsFailed += 1;
              //   continue nextTx;
              // };
              ownersCache[j] := oid;
            };
          };
        };
        // list of new subaccounts to be written after full validation
        var newSubaccounts = List.nil<(OwnerId, T.SubaccountId, SubaccountState)>();
        // pass #1: validation
        for (j in tx.map.keys()) {
          let (contribution, oid) = (tx.map[j], ownersCache[j]);
          for ((subaccountId, flowAsset, isInflow) in u.iterConcat(
            Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.inflow.vals(), func (sid, ast) = (sid, ast, true)),
            Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.outflow.vals(), func (sid, ast) = (sid, ast, false)),
          )) {
            switch (processFlow(oid, subaccountId, contribution.autoApprove, flowAsset, isInflow)) {
              case (#err err) {
                results[i] := #err(err);
                __txsFailed += 1;
                continue nextTx;
              };
              case (#ok newState) newSubaccounts := List.push((oid, subaccountId, newState), newSubaccounts);
            };
          };
        };
        // pass #2: applying
        for ((oid, subaccountId, newSubaccount) in List.toIter(newSubaccounts)) {
          accounts[oid][subaccountId] := newSubaccount;
        };
        __txsSucceeded += 1;
      };
      batchHistory.put({ batchNumber = __totalBatchesProcessed; precedingTotalTxAmount = __txsTotal - results.size(); results = Array.freeze(results) });
      __batchesProcessedPerAggregator[aggregatorIndex] += 1;
      __totalBatchesProcessed += 1;
    };

    private func processFlow(ownerId: OwnerId, subaccountId: T.SubaccountId, autoApprove: Bool, flowAsset: T.Asset, isInflow: Bool): R.Result<SubaccountState, ProcessingError> {
      if (subaccountId >= accounts[ownerId].size()) {
        return #err(#WrongSubaccountId);
      };
      let subaccount = accounts[ownerId][subaccountId];
      if (isInflow and autoApprove and not subaccount.autoApprove) {
        return #err(#AutoApproveNotAllowed);
      };
      switch (flowAsset) {
        case (#none) return #err(#WrongAssetType);
        case (#ft flowAssetData) {
          switch (subaccount.asset) {
            case (#ft userAssetData) {
              // subaccount has some tokens: check asset type
              if (flowAssetData.0 != userAssetData.0) {
                return #err(#WrongAssetType);
              };
              if (isInflow) {
                return #ok({ asset = #ft(flowAssetData.0, userAssetData.1 + flowAssetData.1); autoApprove = subaccount.autoApprove });
              };
              // check is enough balance
              if (userAssetData.1 < flowAssetData.1) {
                return #err(#InsufficientFunds);
              };
              return #ok({ asset = #ft(flowAssetData.0, userAssetData.1 - flowAssetData.1); autoApprove = subaccount.autoApprove });
            };
            case (#none) {
              // subaccount not initialized: inflow always valid, outflow cannot be applied
              if (isInflow) {
                return #ok({ asset = #ft(flowAssetData.0, flowAssetData.1); autoApprove = subaccount.autoApprove });
              };
              return #err(#InsufficientFunds);
            };
          };
        };
      };
    };

    // ============================== INTERNAL STATE ==============================
    // list of all aggregators by their principals
    public var aggregators: [Principal] = initialAggregators;
    // The map from principal to short id is stored in a single `RBTree`:
    let owners : RBTree.RBTree<Principal, OwnerId> = RBTree.RBTree<Principal, OwnerId>(compare);
    // track size of owners RBTree;
    var ownersAmount : Nat = 0;

    /*
    The content of all accounts is stored in an array of arrays.
    The first index is the owner id and the second index is the subaccount id
    For example, a particular balance in a fungible token is accessed like this:
      let #ft(id, balance) = accounts[owner_id][subaccount_id]

    The outer array is of fixed-length N (currently, N=2**24).
    This means there is space for N different owners and N cannot grow.
    In the future we will replace this with our own implementation of an array that can grow.
    The currently available implementations Array and Buffer perform bad in their worst-case when it comes to extending them.

    When an owner open new subaccounts then we use Array.append to grow the owners array of subaccounts.
    We accept the inefficiency of that implementation until there is a better alternative.
    Since this isn't happening in a loop and happens only once during the canister call it is fine.
    */
    public let accounts : [var [var SubaccountState]] = Array.init(C.maxPrincipals, [var] : [var SubaccountState]);

    /* history of last processed transactions */
    let batchHistory: CircularBuffer.CircularBuffer<BatchHistoryEntry> = CircularBuffer.CircularBuffer<BatchHistoryEntry>(C.batchHistoryLength);

    // debug counters
    var __totalBatchesProcessed: Nat = 0;
    var __batchesProcessedPerAggregator: [var Nat] = Array.init(initialAggregators.size(), 0);

    var __txsSucceeded: Nat = 0;
    var __txsFailed: Nat = 0;
    var __txsTotal: Nat = 0;

  };
};
