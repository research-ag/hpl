import E "mo:base/ExperimentalInternetComputer";

import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Array "mo:base/Array";
import { compare } "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Error "mo:base/Error";

// type imports
// pattern matching is not available for types during import (work-around required)
import T "../shared/types";
import C "../shared/constants";
import v "../shared/validators";
import u "../shared/utils";
import DLL "../shared/dll";
import CircularBuffer "../shared/circular_buffer";

// ledger
// the constructor arguments are:
//   initial list of the canister ids of the aggregators
// more can be added later with addAggregator()
// the constructor arguments are passed like this:
//   dfx deploy --argument='(vec { principal "aaaaa-aa"; ... })' ledger
actor class Ledger(initialAggregators : [Principal]) {

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type GlobalId = T.GlobalId;
  type AssetId = T.AssetId;
  type Asset = T.Asset;
  type Batch = T.Batch;

  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  type OwnerId = Nat;

  // data structures

  // list of all aggregators by their principals
  var aggregators: [Principal] = initialAggregators;

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

  type SubaccountState = { asset: Asset; autoApprove: Bool };

  let accounts : [var [var SubaccountState]] = Array.init(C.maxPrincipals, [var] : [var SubaccountState]);

  /* history of last processed transactions */
  type BatchHistoryEntry = { batchNumber: Nat; precedingTotalTxAmount: Nat; results: [Result<(), ProcessingError>] };
  let batchHistory: CircularBuffer.CircularBuffer<BatchHistoryEntry> = CircularBuffer.CircularBuffer<BatchHistoryEntry>(C.batchHistoryLength);

  // ============================== DEBUG COUNTERS ==============================
  var __totalBatchesProcessed: Nat = 0;
  var __batchesProcessedPerAggregator: [var Nat] = Array.init(initialAggregators.size(), 0);

  var __txsSucceeded: Nat = 0;
  var __txsFailed: Nat = 0;
  var __txsTotal: Nat = 0;


  // updates

  /*
  Open n new subaccounts. When `autoApprove` is true then all subaccounts will be set to be "auto approving".
  This setting cannot be changed anymore afterwards with the current API.

  Note that the owner does not specify a token id. The new subaccounts hold the Asset value none.
  The token id of a subaccount is determined by the first inflow.
  After that, the token id cannot be changed anymore with the current API.
  For any subsequent transaction the inflow has to match the token id of the subaccount or else is rejected.

  If the owner wants to set a subaccount's token id before the first inflow then the owner can make a transaction that has no inflows and an outflow of the token id and amount 0.
  That will set the Asset value in the subaccount to the wanted token id.
  */
  public shared({caller}) func openNewAccounts(n: Nat, autoApprove : Bool): async Result<SubaccountId, { #NoSpace; }> {
    var ownerId: ?OwnerId = null;
    // get or register owner ID
    switch (owners.get(caller)) {
      case (?oid) ownerId := ?oid;
      case (null) {
        let regResult = registerAccount(caller);
        switch (regResult) {
          case (#err _) {};
          case (#ok (oid, _)) ownerId := ?oid;
        };
      };
    };
    // update accounts
    switch (ownerId) {
      case (null) #err(#NoSpace);
      case (?oid) {
        let oldSize = accounts[oid].size();
        if (oldSize + n > C.maxSubaccounts) {
          return #err(#NoSpace);
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

  /*
  Process a batch of transactions. Each transaction only executes if the following conditions are met:
  - all subaccounts that are marked `autoApprove` in the transactions are also autoApprove in the ledger
  - all outflow subaccounts have matching token id and sufficient balance
  - all inflow subaccounts have matching token id (or Asset value `none`)
  - on a per-token id basis the sum of all outflows matches all inflows
  There is no return value.
  If the call returns (i.e. no system-level failure) the aggregator knows that the batch has been processed.
  If the aggregator catches a system-level failure then it knows that the batch has not been processed.
  */
  type ProcessingError = v.TxValidationError or { #WrongOwnerId; #WrongSubaccountId; #InsufficientFunds; };
  public shared({caller}) func processBatch(batch: Batch): async () {
    let aggId = u.arrayFindIndex(aggregators, func (agg: Principal): Bool = agg == caller);
    switch (aggId) {
      case (#Found index) __batchesProcessedPerAggregator[index] += 1;
      case (#NotFound) throw Error.reject("Not a registered aggregator");
    };
    _processBatch(batch);
  };

  private func _processBatch(batch: Batch): () {
    let results: [var Result<(), ProcessingError>] = Array.init<Result<(), ProcessingError>>(batch.size(), #ok());
    label nextTx
    for (i in batch.keys()) {
      __txsTotal += 1;
      let tx = batch[i];
      let validationResult = v.validateTx(tx);
      if (R.isErr(validationResult)) {
          results[i] := validationResult;
          __txsFailed += 1;
          continue nextTx;
      };
      // cache owner ids per contribution. If some owner ID is wrong - return error
      let ownersCache: [var OwnerId] = Array.init(tx.map.size(), 0);
      for (j in ownersCache.keys()) {
        switch (owners.get(tx.map[j].owner)) {
          case (null) {
            results[i] := #err(#WrongOwnerId);
            __txsFailed += 1;
            continue nextTx;
          };
          case (?oid) ownersCache[j] := oid;
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
    __totalBatchesProcessed += 1;
  };

  // queries

  public query func nAggregators(): async Nat { aggregators.size(); };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> {
    if (aggregators.size() >= aid) {
      return #err(#NotFound);
    };
    #ok(aggregators[aid]);
  };

  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> {
    switch (owners.get(caller)) {
      case (null) #err(#NotFound);
      case (?oid) #ok(accounts[oid].size());
    };
  };

  public shared query ({caller}) func asset(sid: SubaccountId): async Result<SubaccountState, { #NotFound; #SubaccountNotFound; }> {
    switch (owners.get(caller)) {
      case (null) #err(#NotFound);
      case (?oid) {
        if (sid >= accounts[oid].size()) {
          return #err(#SubaccountNotFound);
        };
        #ok(accounts[oid][sid]);
      };
    };
  };

  // admin interface
  // TODO admin-only authorization

  // add one aggregator principal
  public func addAggregator(p : Principal) : async Result<AggregatorId,()> {
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
    #ok(aggregators.size() - 1);
  };

  public func issueTokens(userPrincipal: Principal, subaccountId: SubaccountId, asset: Asset) : async Result<SubaccountState,ProcessingError> {
    switch (owners.get(userPrincipal)) {
      case (null) #err(#WrongOwnerId);
      case (?oid) {
        switch (processFlow(oid, subaccountId, false, asset, true)) {
          case (#err err) #err(err);
          case (#ok newState) {
            accounts[oid][subaccountId] := newState;
            #ok(newState);
          };
        };
      };
    };
  };

  // debug interface
  public query func allAssets(owner : Principal) : async Result<[SubaccountState], { #NotFound; }> {
    switch (owners.get(owner)) {
      case (null) #err(#NotFound);
      case (?oid) #ok(Array.freeze(accounts[oid]));
    };
  };

  public query func counters() : async { totalBatches: Nat; batchesPerAggregator: [Nat]; totalTxs: Nat; failedTxs: Nat; succeededTxs: Nat } {
    {
      totalBatches = __totalBatchesProcessed;
      batchesPerAggregator = Array.freeze<Nat>(__batchesProcessedPerAggregator);
      totalTxs = __txsTotal;
      failedTxs = __txsFailed;
      succeededTxs = __txsSucceeded;
    };
  };

  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [BatchHistoryEntry] {
    batchHistory.slice(startIndex, endIndex);
  };

  // private functionality

  private func registerAccount(principal: Principal) : Result<(OwnerId, [var SubaccountState]), { #NoSpace }> {
    let ownerId = ownersAmount;
    if (ownerId >= C.maxPrincipals) {
      return #err(#NoSpace);
    };
    owners.put(principal, ownerId);
    ownersAmount += 1;
    accounts[ownerId] := Array.init<SubaccountState>(0, { asset = #none; autoApprove = false; });
    #ok(ownerId, accounts[ownerId]);
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

  public func profile(batch : Batch): async Nat64 {
    E.countInstructions(func foo() { _processBatch(batch) })  
  }
};
