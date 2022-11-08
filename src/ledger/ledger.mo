import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Array "mo:base/Array";
import { compare } "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";

import Tx "../shared/transaction";
import u "../shared/utils";
import CircularBuffer "../shared/circular_buffer";
import C "../shared/constants";

module {
  public type Result<X,Y> = R.Result<X,Y>;
  public type AggregatorId = Nat;

  public type SubaccountId = Tx.SubaccountId;
  public type Asset = Tx.Asset;
  public type AssetId = Tx.AssetId;
  public type Batch = Tx.Batch;

  public type SubaccountState = { asset: Asset };
  public type ProcessingError = Tx.TxError or { 
    #UnknownPrincipal; // not yet registered 
    #UnknownSubaccount; // not yet registered  
    #UnknownFtAsset; // not yet registered 
    #MismatchInAsset; // asset in flow != asset in subaccount 
    #InsufficientFunds; 
    #NotAController;  // attempted mint operation
  };
  public type ImmediateTxError = ProcessingError or { 
    #TxHasToBeApproved; 
  }; 
  public type BatchHistoryEntry = { 
    batchNumber: Nat; 
    precedingTotalTxAmount: Nat; 
    results: [Result<(), ProcessingError>] 
  };
  public type CreateFtError = { #NoSpace; #FeeError };
  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  public type OwnerId = Nat;

  public let constants = {
    // maximum number of asset ids that the ledger can register
    maxAssets = C.maxAssets; 

    // maximum number of subaccounts per owner
    maxSubaccounts = C.maxSubaccounts; 

    // maximum number of stored latest processed batches on the ledger
    batchHistoryLength = 1024;

    // maximum number of accounts total in the ledger
    maxPrincipals = 16777216; // 2**24
  };

  public class Ledger(initialAggregators : [Principal]) {

    // ================================ ACCESSORS =================================
    // TODO: move this to stats()
    public func nAggregators(): Nat = aggregators.size();

    public func aggregatorPrincipal(aid: AggregatorId): Result<Principal, { #NotFound; }> =
      switch (aggregators.size() > aid) {
        case (true) #ok(aggregators[aid]);
        case (_) #err(#NotFound);
      };

    // internal accessors based on owner id

    func nAccounts_(oid : OwnerId) : Nat = 
      accounts[oid].size();

    func asset_(oid : OwnerId, sid: SubaccountId): Result<SubaccountState, { #SubaccountNotFound }> =
      switch (accounts[oid].size() > sid) {
        case (true) #ok(accounts[oid][sid]);
        case (false) #err(#SubaccountNotFound)
      };

    func assetInSubaccount_(sid: SubaccountId) : OwnerId -> Result<SubaccountState, { #SubaccountNotFound }> =
      func(oid) = asset_(oid, sid);

    func allAssets_(oid : OwnerId) : [SubaccountState] =
      Array.freeze(accounts[oid]);

    // public accessors based on principal

    public func ownerId(p: Principal): Result<OwnerId, { #UnknownPrincipal }> =
      R.fromOption(owners.get(p), #UnknownPrincipal); 

    public func nAccounts(p: Principal): Result<Nat, { #UnknownPrincipal }> =
      R.mapOk(ownerId(p), nAccounts_);

    public func asset(p: Principal, sid: SubaccountId): Result<SubaccountState, { #UnknownPrincipal; #SubaccountNotFound }> = 
      R.chain(ownerId(p), assetInSubaccount_(sid));

    public func allAssets(p : Principal) : Result<[SubaccountState], { #UnknownPrincipal }> =
      R.mapOk(ownerId(p), allAssets_);

    public func counters() : { nBatchTotal: Nat; nBatchPerAggregator: [Nat]; nTxTotal: Nat; nTxFailed: Nat; nTxSucceeded: Nat; nAssets: Nat } =
      {
        nBatchTotal = nBatchTotal_;
        nBatchPerAggregator = Array.freeze<Nat>(nBatchPerAggregator_);
        nTxTotal = nTxTotal_;
        nTxFailed = nTxFailed_;
        nTxSucceeded = nTxSucceeded_;
        nAssets = ftControllers.size();
      };

    public func batchesHistory(startIndex: Nat, endIndex: Nat) : [BatchHistoryEntry] = batchHistory.slice(startIndex, endIndex);

    // ================================= MUTATORS =================================
    // add one aggregator principal
    public func addAggregator(p : Principal) : AggregatorId {
      aggregators := u.append(aggregators, p);
      nBatchPerAggregator_ := u.appendVar(nBatchPerAggregator_, 1, 0);
      aggregators.size() - 1;
    };

    // only public for the test api
    public func getOrCreateOwnerId(p: Principal): ?OwnerId =
      switch (ownerId(p), ownersAmount >= constants.maxPrincipals) {
        case (#ok oid, _) { ?oid };
        case (#err _, true) { null }; // no space
        case (#err _, false) {
          let newId = ownersAmount;
          owners.put(p, newId);
          ownersAmount += 1;
          ?newId;
        };
      };

    public func createFungibleToken(controller: Principal) : Result<AssetId, CreateFtError> {
      // We ignore errors about the controller in which the controller cannot
      // create any accounts for the new token. This could happen if the
      // controller:
      // - cannot be registered (owner ids are exhausted)
      // - cannot open new subaccounts (has reached maxSubaccounts)
      // If any of this happens then the controller can still approve
      // transactions for the new token. He just cannot hold them himself.
      if (ftControllers.size() >= constants.maxAssets) {
        return #err(#NoSpace);
      };
      let assetId : AssetId = ftControllers.size();
      ftControllers := u.append(ftControllers, controller);
      #ok(assetId);
    };

    public func openNewAccounts(p: Principal, n: Nat, aid: AssetId): Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #UnknownFtAsset }> {
      if (aid >= ftControllers.size()) {
        return #err(#UnknownFtAsset);
      };
      switch (getOrCreateOwnerId(p)) {
        case (null) #err(#NoSpaceForPrincipal);
        case (?oid) {
          let oldSize = accounts[oid].size();
          if (oldSize + n > constants.maxSubaccounts) {
            return #err(#NoSpaceForSubaccount);
          };
          // array.append seems to not work with var type
          accounts[oid] := u.appendVar(accounts[oid], n, {asset = #ft(aid, 0)});
          #ok(oldSize);
        };
      };
    };

    // ================================ PROCESSING ================================
    public func processBatch(aggregatorIndex: Nat, batch: Batch): () {
      let results: [var Result<(), ProcessingError>] = Array.init<Result<(), ProcessingError>>(batch.size(), #ok());
      for (i in batch.keys()) {
        let res = processTx(batch[i]);
        switch (res) {
          case (#ok) { nTxSucceeded_ += 1 };
          case (#err(_)) { nTxFailed_ += 1 };
        };
        nTxTotal_ += 1;
        results[i] := res; 
      };
      batchHistory.put({ batchNumber = nBatchTotal_; precedingTotalTxAmount = nTxTotal_ - results.size(); results = Array.freeze(results) });
      nBatchPerAggregator_[aggregatorIndex] += 1;
      nBatchTotal_ += 1;
    };

    public func processImmediateTx(caller: Principal, tx: Tx.Tx): Result<(), ImmediateTxError> =
      switch (Tx.validate(tx, false)) {
        case (#ok _) {
          for (c in tx.map.vals()) {
            if (c.owner != caller and (c.outflow.size() > 0 or c.mints.size() > 0 or c.burns.size() > 0)) {
              return #err(#TxHasToBeApproved);
            };
          };
          processTx(tx)
        };
        case (#err e) { #err e }
      };

    private func processTx(tx: Tx.Tx): Result<(), ProcessingError> {
      // disabled validation, performed on the aggregator side. The ledger still validates:
      // - owner Id-s
      // - subaccount Id-s
      // - auto-approve flag
      // - asset type
      // - is balance sufficient

      // cache owner ids per contribution. If some owner ID is wrong - return error
      let ownersCache: [var OwnerId] = Array.init(tx.map.size(), 0);
      // checking uniqueness (disabled now, since aggregator alredy checked principal uniqueness)
      // let ownerIdsSet = LinkedListSet.LinkedListSet<Nat>(Nat.equal);
      for (j in ownersCache.keys()) {
        switch (owners.get(tx.map[j].owner)) {
          case (null) {
            return #err(#UnknownPrincipal);
          };
          case (?oid) {
            // if (not ownerIdsSet.put(oid)) {
            //   return #err(#OwnersNotUnique);
            // };
            ownersCache[j] := oid;
          };
        };
      };
      // list of new subaccounts to be written after full validation
      var newSubaccounts = List.nil<(OwnerId, SubaccountId, SubaccountState)>();
      // pass #1: validation
      for (j in tx.map.keys()) {
        let (contribution, oid) = (tx.map[j], ownersCache[j]);
        // mints/burns should be only validated, they do not affect any subaccounts
        for (mintBurnAsset in u.iterConcat(contribution.mints.vals(), contribution.burns.vals())) {
          switch (mintBurnAsset) {
            case (#ft ft) {
              if (contribution.owner != ftControllers[ft.0]) {
                return #err(#NotAController);
              };
            }
          };
        };
        for ((subaccountId, flowAsset, isInflow) in u.iterConcat(
          Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.inflow.vals(), func (sid, ast) = (sid, ast, true)),
          Iter.map<(SubaccountId, Asset), (SubaccountId, Asset, Bool)>(contribution.outflow.vals(), func (sid, ast) = (sid, ast, false)),
        )) {
          switch (processFlow(oid, subaccountId, flowAsset, isInflow)) {
            case (#err err) {
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
      #ok();
    };

    private func processFlow(ownerId: OwnerId, subaccountId: SubaccountId, flowAsset: Asset, isInflow: Bool): R.Result<SubaccountState, ProcessingError> {
      if (subaccountId >= accounts[ownerId].size()) {
        return #err(#UnknownSubaccount);
      };
      let subaccount = accounts[ownerId][subaccountId];
      switch (flowAsset) {
        case (#ft flowAssetData) {
          switch (subaccount.asset) {
            case (#ft userAssetData) {
              // subaccount has some tokens: check asset type
              if (flowAssetData.0 != userAssetData.0) {
                return #err(#MismatchInAsset);
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

    When an owner open new subaccounts then we grow the owners array of subaccounts.
    */
    public let accounts : [var [var SubaccountState]] = Array.init(constants.maxPrincipals, [var] : [var SubaccountState]);

    /* history of last processed transactions */
    let batchHistory: CircularBuffer.CircularBuffer<BatchHistoryEntry> = CircularBuffer.CircularBuffer<BatchHistoryEntry>(constants.batchHistoryLength);

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
