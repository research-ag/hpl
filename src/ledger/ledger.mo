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

module {

  public type Batch = T.Batch;
  public type Result<X,Y> = R.Result<X,Y>;
  public type AggregatorId = T.AggregatorId;
  public type SubaccountId = T.SubaccountId;
  public type Asset = T.Asset;
  public type AssetId = T.AssetId;

  public type SubaccountState = { asset: Asset };
  public type TxValidationError = v.TxValidationError;
  public type ProcessingError = TxValidationError or { #OwnerIdUnknown; #SubaccountIdUnknown; #InsufficientFunds; #AssetIdUnknown; #AssetIdMismatch; #NotAController; };
  public type ImmediateTxError = ProcessingError or { #TxHasToBeApproved; };
  public type BatchHistoryEntry = { batchNumber: Nat; precedingTotalTxAmount: Nat; results: [Result<(), ProcessingError>] };
  public type CreateFtError = { #NoSpace; #FeeError };
  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  public type OwnerId = Nat;
  public type Tx = T.Tx;

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

    public func counters() : { nBatchTotal: Nat; nBatchPerAggregator: [Nat]; nTxTotal: Nat; nTxFailed: Nat; nTxSucceeded: Nat } =
      {
        nBatchTotal = nBatchTotal_;
        nBatchPerAggregator = Array.freeze<Nat>(nBatchPerAggregator_);
        nTxTotal = nTxTotal_;
        nTxFailed = nTxFailed_;
        nTxSucceeded = nTxSucceeded_;
      };

    public func batchesHistory(startIndex: Nat, endIndex: Nat) : [BatchHistoryEntry] = batchHistory.slice(startIndex, endIndex);

    // ================================= MUTATORS =================================
    // add one aggregator principal
    public func addAggregator(p : Principal) : AggregatorId {
      // AG: Array.append is deprecated due to bad performance, however in this case it appears more optimal than converting to buffer
      aggregators := Array.append(aggregators, [p]);
      // for var arrays, even append does not exists...
      nBatchPerAggregator_ := Array.tabulateVar<Nat>(nBatchPerAggregator_.size() + 1, func (i : Nat) : Nat {
        if (i < nBatchPerAggregator_.size()) {
          nBatchPerAggregator_[i];
        } else {
          0;
        };
      });
      aggregators.size() - 1;
    };

    public func getOwnerId(p: Principal, autoRegister: Bool): Result<OwnerId, { #NoSpaceForPrincipal; #NotFound }> =
      switch (owners.get(p)) {
        case (?oid) #ok(oid);
        case (null)
          switch (autoRegister) {
            case (true) registerAccount(p);
            case (_) #err(#NotFound);
        };
      };

    public func createFungibleToken(controller: Principal) : Result<AssetId, CreateFtError> {
      // register controller, if not registered yet
      let _ = getOwnerId(controller, true);
      let assetId: AssetId = ftControllers.size();
      if (assetId >= C.maxAssetIds) {
        return #err(#NoSpace);
      };
      ftControllers := Array.append(ftControllers, [controller]);
      #ok(assetId);
    };

    public func openNewAccounts(p: Principal, n: Nat, assetId: AssetId): Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #AssetIdUnknown }> {
      if (assetId >= ftControllers.size()) {
        return #err(#AssetIdUnknown);
      };
      switch (getOwnerId(p, true)) {
        case (#err _) #err(#NoSpaceForPrincipal);
        case (#ok oid) {
          let oldSize = accounts[oid].size();
          if (oldSize + n > C.maxSubaccounts) {
            return #err(#NoSpaceForSubaccount);
          };
          // array.append seems to not work with var type
          accounts[oid] := Array.tabulateVar<SubaccountState>(oldSize + n, func (n: Nat) =
            switch (n < oldSize) {
              case (true) accounts[oid][n];
              case (_) ({ asset = #ft(assetId, 0) });
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
      #ok(ownerId);
    };

    // ================================ PROCESSING ================================
    public func processBatch(aggregatorIndex: Nat, batch: Batch): () {
      let results: [var Result<(), ProcessingError>] = Array.init<Result<(), ProcessingError>>(batch.size(), #ok());
      for (i in batch.keys()) {
        results[i] := processTx(batch[i]);
      };
      batchHistory.put({ batchNumber = nBatchTotal_; precedingTotalTxAmount = nTxTotal_ - results.size(); results = Array.freeze(results) });
      nBatchPerAggregator_[aggregatorIndex] += 1;
      nBatchTotal_ += 1;
    };

    public func processImmediateTx(caller: Principal, tx: Tx): Result<(), ImmediateTxError> {
      let validationResult = v.validateTx(tx, false);
      switch (validationResult) {
        case (#err error) return #err(error);
        case (#ok _) {};
      };
      for (c in tx.map.vals()) {
        if (c.owner != caller and (c.outflow.size() > 0 or c.mints.size() > 0)) {
          return #err(#TxHasToBeApproved);
        };
      };
      processTx(tx);
    };

    private func processTx(tx: Tx): Result<(), ProcessingError> {
      // disabled validation, performed on the aggregator side. The ledger still validates:
      // - owner Id-s
      // - subaccount Id-s
      // - auto-approve flag
      // - asset type
      // - is balance sufficient

      // let validationResult = v.validateTx(tx, false);
      // if (R.isErr(validationResult)) {
      //     nTxFailed_ += 1;
      //     return validationResult;
      // };

      // cache owner ids per contribution. If some owner ID is wrong - return error
      let ownersCache: [var OwnerId] = Array.init(tx.map.size(), 0);
      // checking uniqueness (disabled now, since aggregator alredy checked principal uniqueness)
      // let ownerIdsSet = LinkedListSet.LinkedListSet<Nat>(Nat.equal);
      for (j in ownersCache.keys()) {
        switch (owners.get(tx.map[j].owner)) {
          case (null) {
            nTxFailed_ += 1;
            return #err(#OwnerIdUnknown);
          };
          case (?oid) {
            // if (not ownerIdsSet.put(oid)) {
            //   nTxFailed_ += 1;
            //   return #err(#OwnersNotUnique);
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
        // mints/burns should be only validated, they do not affect any subaccounts
        for (mintBurnAsset in u.iterConcat(contribution.mints.vals(), contribution.burns.vals())) {
          switch (mintBurnAsset) {
            case (#ft ft) {
              if (contribution.owner != ftControllers[ft.0]) {
                nTxFailed_ += 1;
                return #err(#NotAController);
              };
            };
            case _ {
              nTxFailed_ += 1;
              return #err(#AssetIdMismatch);
            };
          };
        };
        for ((subaccountId, flowAsset, isInflow) in u.iterConcat(
          Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.inflow.vals(), func (sid, ast) = (sid, ast, true)),
          Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.outflow.vals(), func (sid, ast) = (sid, ast, false)),
        )) {
          switch (processFlow(oid, subaccountId, flowAsset, isInflow)) {
            case (#err err) {
              nTxFailed_ += 1;
              return #err(err);
            };
            case (#ok newState) newSubaccounts := List.push((oid, subaccountId, newState), newSubaccounts);
          };
        };
      };
      // pass #2: applying
      for ((oid, subaccountId, newSubaccount) in List.toIter(newSubaccounts)) {
        accounts[oid][subaccountId] := newSubaccount;
      };
      nTxSucceeded_ += 1;
      nTxTotal_ += 1;
      #ok();
    };

    private func processFlow(ownerId: OwnerId, subaccountId: T.SubaccountId, flowAsset: T.Asset, isInflow: Bool): R.Result<SubaccountState, ProcessingError> {
      if (subaccountId >= accounts[ownerId].size()) {
        return #err(#SubaccountIdUnknown);
      };
      let subaccount = accounts[ownerId][subaccountId];
      switch (flowAsset) {
        case (#ft flowAssetData) {
          switch (subaccount.asset) {
            case (#ft userAssetData) {
              // subaccount has some tokens: check asset type
              if (flowAssetData.0 != userAssetData.0) {
                return #err(#AssetIdMismatch);
              };
              if (isInflow) {
                return #ok({ asset = #ft(flowAssetData.0, userAssetData.1 + flowAssetData.1) });
              };
              // check is enough balance
              if (userAssetData.1 < flowAssetData.1) {
                return #err(#InsufficientFunds);
              };
              return #ok({ asset = #ft(flowAssetData.0, userAssetData.1 - flowAssetData.1) });
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

    // asset ids
    public var ftControllers: [Principal] = [];

    // debug counters
    var nBatchTotal_: Nat = 0;
    var nBatchPerAggregator_: [var Nat] = Array.init(initialAggregators.size(), 0);
    var nTxSucceeded_: Nat = 0;
    var nTxFailed_: Nat = 0;
    var nTxTotal_: Nat = 0;

  };
};
