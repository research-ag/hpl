import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";

import Tx "../shared/transaction";
import u "../shared/utils";
import { CircularBuffer } "../shared/circular_buffer";
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
    #MissingApproval; 
  }; 
  public type BatchHistoryEntry = { 
    batchNumber: Nat; 
    txNumberOffset: Nat; 
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

  // tx counter (used once per source)
  type CtrState = { batches: Nat; txs: Nat; txsFailed: Nat; txsSucceeded: Nat };

  class Ctr() {
    public var batches : Nat = 0;
    public var txs : Nat = 0;
    public var txsFailed : Nat = 0;
    public var txsSucceeded : Nat = 0;

    public func record(event : {#batch; #txfail; #txsuccess}) =
      switch (event) {
        case (#batch) { 
          batches += 1; 
        };
        case (#txfail) { 
          txsFailed += 1;
          txs += 1;
        };
        case (#txsuccess) {
          txsSucceeded += 1;
          txs += 1;
        }
      };

    public func state() : CtrState = {
      batches = batches;
      txs = txs;
      txsFailed = txsFailed;
      txsSucceeded = txsSucceeded;
    };
  };

  // global stats
  public type Stats = { perAgg : [CtrState]; direct : CtrState; all : CtrState; registry : { owners : Nat; accounts : Nat; assets : Nat }};

  public class Ledger(initialAggregators : [Principal]) {

    // stats bundles all values that are collected with the purpose of making them available to outside observers
    // they are not used internally and have no relevance for the operation of the ledger
    let stats_ = object {
      public var perAgg : [Ctr] = Array.tabulate<Ctr>(initialAggregators.size(), func(i) { Ctr() });
      public var direct : Ctr = Ctr();
      public var all : Ctr = Ctr();
      public var accounts : Nat = 0;

      public func record(source: {#agg : Nat; #direct}, event : {#batch; #txfail; #txsuccess}) {
        switch source {
          case (#agg i) perAgg[i].record(event);
          case (#direct) direct.record(event)
        };
        all.record(event);
      };

      public func add(item : {#accounts : Nat}) =
        switch item {
          case (#accounts(n)) accounts += n
        };

      public func get() : Stats = {
        perAgg = Array.tabulate<CtrState>(perAgg.size(), func(i) { perAgg[i].state() });
        direct = direct.state();
        all = all.state();
        registry = { owners = counters_.owners; accounts = accounts; assets = counters_.assets }
      }
    };

    // counters bundles those counter values on which the ledger operation depends 
    let counters_ = object {
      public var assets : Nat = 0;
      public var owners : Nat = 0;

      public func add(item : {#owner; #asset}) : Nat =
        switch item {
          case (#owner) { let n = owners; owners += 1; n }; 
          case (#asset) { let n = assets; assets += 1; n }
        };

      public func hasSpace(item : {#owner; #asset}) : Bool =
        switch item {
          case (#owner) owners <= constants.maxPrincipals;
          case (#asset) assets <= constants.maxAssets
        }
    };

    // ================================ ACCESSORS =================================
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

    public func stats() : Stats = stats_.get(); 

    public func batchesHistory(startIndex: Nat, endIndex: Nat) : [BatchHistoryEntry] = batchHistory.slice(startIndex, endIndex);

    // ================================= MUTATORS =================================
    // add one aggregator principal
    public func addAggregator(p : Principal) : AggregatorId {
      aggregators := u.append(aggregators, p);
      stats_.perAgg := u.append(stats_.perAgg, Ctr());
      aggregators.size() - 1;
    };

    // only public for the test api
    public func getOrCreateOwnerId(p: Principal): ?OwnerId =
      switch (ownerId(p), counters_.hasSpace(#owner)) {
        case (#ok oid, _) { ?oid };
        case (#err _, false) { null }; // no space
        case (#err _, true) {
          let newId = counters_.add(#owner);
          owners.put(p, newId);
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
      if (not counters_.hasSpace(#asset)) {
        return #err(#NoSpace);
      };
      ftControllers := u.append(ftControllers, controller);
      #ok(counters_.add(#asset));
    };

    public func openNewAccounts(p: Principal, n: Nat, aid: AssetId): Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #UnknownFtAsset }> {
      if (aid >= counters_.assets) {
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
          stats_.add(#accounts(n));
          #ok(oldSize);
        };
      };
    };

    // ================================ PROCESSING ================================
    func processBatch_(source: {#agg : Nat; #direct}, batch: Batch): [Result<(), ProcessingError>] {
      let results : [var Result<(), ProcessingError>] = Array.init(batch.size(), #ok());
      for (i in batch.keys()) {
        let res = processTx(batch[i]);
        switch (res) {
          case (#ok) { stats_.record(source, #txsuccess) };
          case (#err(_)) { stats_.record(source, #txfail) };
        };
        results[i] := res; 
      };
      batchHistory.put({ batchNumber = stats_.all.batches; txNumberOffset = stats_.all.txs - results.size(); results = Array.freeze(results) });
      stats_.record(source, #batch);
      Array.freeze(results)
    };

    public func processBatch(aggId: Nat, batch: Batch): () =
      ignore processBatch_(#agg(aggId), batch);

    public func processImmediateTx(caller: Principal, tx: Tx.Tx): Result<(), ImmediateTxError> =
      switch (Tx.validate(tx, true)) {
        case (#ok _) {
          for (c in tx.map.vals()) {
            if (c.owner != caller and (c.outflow.size() > 0 or c.mints.size() > 0 or c.burns.size() > 0)) {
              return #err(#MissingApproval);
            };
          };
          return processBatch_(#direct, [tx])[0]
        };
        case (#err e) { 
          return #err(e) 
        }
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
          if (flowAssetData.0 >= counters_.assets) {
            return #err(#UnknownFtAsset);
          };
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
    let owners : RBTree.RBTree<Principal, OwnerId> = RBTree.RBTree<Principal, OwnerId>(Principal.compare);

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
    let batchHistory = CircularBuffer<BatchHistoryEntry>(constants.batchHistoryLength);

    // asset ids
    public var ftControllers: [Principal] = [];

  };
};
