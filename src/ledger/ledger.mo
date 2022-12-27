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
import Stats "ledger-stats";

module {
  public type Result<X,Y> = R.Result<X,Y>;
  public type AggregatorId = Nat;

  public type SubaccountId = Tx.SubaccountId;
  public type VirtualAccountId = Tx.VirtualAccountId;
  public type AccountReference = Tx.AccountReference;
  public type Asset = Tx.Asset;
  public type AssetId = Tx.AssetId;
  public type Batch = Tx.Batch;

  public type SubaccountState = { asset: Asset };
  public type VirtualAccountState = { asset: Asset; backingSubaccountId: SubaccountId; remotePrincipal: Principal };
  public type ProcessingError = Tx.TxError or {
    // Errors that start with "Unknown" mean that
    // a value has not yet been registered
    #UnknownPrincipal;
    #UnknownSubaccount;
    #UnknownVirtualAccount;
    #UnknownFtAsset;
    #MismatchInAsset; // asset in flow != asset in account
    #MismatchInRemotePrincipal; // remotePrincipal in flow != remotePrincipal in virtual account
    #InsufficientFunds;
    #NotAController;  // in attempted mint operation
  };
  public type ImmediateTxError = ProcessingError or {
    #MissingApproval;
  };
  public type BatchHistoryEntry = {
    batchNumber: Nat;
    txNumberOffset: Nat;
    results: [Result<(), ProcessingError>]
  };
  public type CreateFtError = {
    #NoSpace;
    #FeeError
  };
  public type Stats = Stats.Stats;

  // Owners are tracked via a "short id" which is a Nat
  // Short ids (aka owner ids) are issued consecutively
  public type OwnerId = Nat;

  public let constants = {
    // maximum number of owner ids that the ledger can register
    maxPrincipals = 16777216; // 2**24

    // maximum number of subaccounts per owner
    maxSubaccounts = C.maxSubaccounts;

    // maximum number of virtual accounts per principal
    maxVirtualAccounts = C.maxVirtualAccounts;

    // maximum number of asset ids that the ledger can register
    maxAssets = C.maxAssets;

    // maximum number of stored latest processed batches on the ledger
    batchHistoryLength = 1024;
  };

  public class Ledger(initialAggregators : [Principal]) {

    // tracker bundles all values that are collected with the purpose of making them available to outside observers
    // they are not used internally and have no relevance for the operation of the ledger
    let tracker = Stats.Tracker(initialAggregators.size());

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
        };

      public func isKnown(item : {#owner; #asset}, i : Nat) : Bool =
        switch item {
          case (#owner) i < owners;
          case (#asset) i < assets
        }
    };

    // ================================ ACCESSORS =================================
    // get the principal of aggregator specified by aggregtor id
    public func aggregatorPrincipal(aid: AggregatorId): Result<Principal, { #NotFound; }> =
      switch (aid < aggregators.size()) {
        case (true) #ok(aggregators[aid]);
        case (_) #err(#NotFound);
      };

    // internal accessors based on owner id
    // they assume that the owner id exists and will trap otherwise

    // get the number of subaccounts of a given owner id
    func nAccounts_(oid : OwnerId) : Nat =
      accounts[oid].size();

    // get the asset in a given subaccount
    func asset_(oid : OwnerId, sid: SubaccountId): Result<SubaccountState, { #UnknownSubaccount }> =
      switch (accounts[oid].size() > sid) {
        case (true) #ok(accounts[oid][sid]);
        case (false) #err(#UnknownSubaccount)
      };
    // get the state of virtual account
    func virtualAsset_(oid : OwnerId, vid: VirtualAccountId): Result<VirtualAccountState, { #UnknownVirtualAccount }> =
      switch (virtualAccounts[oid].size() > vid) {
        case (true) switch (virtualAccounts[oid][vid]) {
          case (null) #err(#UnknownVirtualAccount);
          case (?acc) #ok(acc);
        };
        case (false) #err(#UnknownVirtualAccount)
      };

    // currying the asset_ function
    func assetInSubaccount_(sid: SubaccountId) : OwnerId -> Result<SubaccountState, { #UnknownSubaccount }> =
      func(oid) = asset_(oid, sid);
    // currying the virtualAsset_ function
    func stateOfVirtualAccount_(vid: VirtualAccountId) : OwnerId -> Result<VirtualAccountState, { #UnknownVirtualAccount }> =
      func(oid) = virtualAsset_(oid, vid);

    // get the assets in all subaccounts of a given owner id
    func allAssets_(oid : OwnerId) : [SubaccountState] =
      Array.freeze(accounts[oid]);

    // public accessors based on principal
    // if the principal is not registered then error #UnknownPrincipal is returned

    // ownerId is an implementation detail and not publicly exposed
    // this function is only public for testing purposes (see ledger_api.mo)
    public func ownerId(p: Principal): Result<OwnerId, { #UnknownPrincipal }> =
      R.fromOption(owners.get(p), #UnknownPrincipal);

    public func nAccounts(p: Principal): Result<Nat, { #UnknownPrincipal }> =
      R.mapOk(ownerId(p), nAccounts_);

    public func asset(p: Principal, sid: SubaccountId): Result<SubaccountState, { #UnknownPrincipal; #UnknownSubaccount }> =
      R.chain(ownerId(p), assetInSubaccount_(sid));

    public func virtualAccount(p: Principal, vid: VirtualAccountId): Result<VirtualAccountState, { #UnknownPrincipal; #UnknownVirtualAccount }> =
      R.chain(ownerId(p), stateOfVirtualAccount_(vid));

    public func allAssets(p : Principal) : Result<[SubaccountState], { #UnknownPrincipal }> =
      R.mapOk(ownerId(p), allAssets_);

    public func stats() : Stats = tracker.get();

    public func batchesHistory(startIndex: Nat, endIndex: Nat) : [BatchHistoryEntry] = batchHistory.slice(startIndex, endIndex);

    // ================================= MUTATORS =================================
    // add one aggregator principal
    // return the id of the newly added aggregator
    public func addAggregator(p : Principal) : AggregatorId {
      let newId = aggregators.size();
      aggregators := u.append(aggregators, p);
      tracker.add(#aggregator);
      newId
    };

    // this function is an internal helper but is made public for testing (see ledger_api.mo)
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

    // open n new subaccounts for the given principal
    // all n new subaccounts are for the same asset id
    public func openNewAccounts(p: Principal, n: Nat, aid: AssetId): Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #UnknownFtAsset }> {
      if (not counters_.isKnown(#asset, aid)) {
        return #err(#UnknownFtAsset);
      };
      switch (getOrCreateOwnerId(p)) {
        case (null) #err(#NoSpaceForPrincipal);
        case (?oid) {
          let oldSize = accounts[oid].size();
          if (oldSize + n > constants.maxSubaccounts) {
            return #err(#NoSpaceForSubaccount);
          };
          accounts[oid] := u.appendVar(accounts[oid], n, {asset = #ft(aid, 0)});
          tracker.add(#accounts(n));
          #ok(oldSize);
        };
      };
    };
    public func openVirtualAccount(p: Principal, state: VirtualAccountState): Result<VirtualAccountId, { #UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset; #NoSpaceForAccount; }> {
      switch (ownerId(p)) {
        case (#err err) #err(err);
        case (#ok oid) {
          let oldSize = virtualAccounts[oid].size();
          if (oldSize >= constants.maxVirtualAccounts) {
            return #err(#NoSpaceForAccount);
          };
          switch (validateVirtualAccountState_(oid, state)) {
            case (#ok) {
              virtualAccounts[oid] := u.appendVar(virtualAccounts[oid], 1, ?state);
              #ok(oldSize);
            };
            case (#err err) #err(err);
          };
        };
      };
    };
    public func updateVirtualAccount(p: Principal, vid: VirtualAccountId, newState: VirtualAccountState): Result<(), { #UnknownPrincipal; #UnknownVirtualAccount; #UnknownSubaccount; #MismatchInAsset }> {
      switch (ownerId(p)) {
        case (#err err) #err(err);
        case (#ok oid) {
          if (vid >= virtualAccounts[oid].size()) {
            return #err(#UnknownVirtualAccount);
          };
          switch (validateVirtualAccountState_(oid, newState)) {
            case (#ok) {
              virtualAccounts[oid][vid] := ?newState;
              #ok(); 
            };
            case (#err err) #err(err);
          };
        };
      };
    };
    public func deleteVirtualAccount(p: Principal, vid: VirtualAccountId): Result<(), { #UnknownPrincipal; #UnknownVirtualAccount; }> {
      switch (ownerId(p)) {
        case (#err err) #err(err);
        case (#ok oid) {
          if (vid >= virtualAccounts[oid].size()) {
            return #err(#UnknownVirtualAccount);
          };
          virtualAccounts[oid][vid] := null;
          #ok(); 
        };
      };
    };
    private func validateVirtualAccountState_(oid: OwnerId, state: VirtualAccountState): Result<(), { #UnknownPrincipal; #UnknownSubaccount; #MismatchInAsset }> {
      if (state.backingSubaccountId >= accounts[oid].size()) {
        return #err(#UnknownSubaccount);
      };
      switch (owners.get(state.remotePrincipal), accounts[oid][state.backingSubaccountId].asset, state.asset) {
        case (null, _, _) {
          #err(#UnknownPrincipal);
        };
        case (_, #ft ft, #ft ft2) {
          if (ft.0 != ft2.0) { 
            return #err(#MismatchInAsset); 
          };
          #ok();
        };
      };
    };

    // ================================ PROCESSING ================================
    // process a batch of txs
    // the batch could have been submitted directly to the ledger or through an aggregator
    func processBatch_(source: {#agg : Nat; #direct}, batch: Batch): [Result<(), ProcessingError>] {
      let results : [var Result<(), ProcessingError>] = Array.init(batch.size(), #ok());
      for (i in batch.keys()) {
        let res = processTx(batch[i]);
        switch (res) {
          case (#ok) { tracker.record(source, #txsuccess) };
          case (#err(_)) { tracker.record(source, #txfail) };
        };
        results[i] := res;
      };
      batchHistory.put({ batchNumber = tracker.all.batches; txNumberOffset = tracker.all.txs - results.size(); results = Array.freeze(results) });
      tracker.record(source, #batch);
      Array.freeze(results)
    };

    // pass through a batch from an aggregator
    public func processBatch(aggId: Nat, batch: Batch): () =
      ignore processBatch_(#agg(aggId), batch);

    // pass through a single directly submitted tx
    public func processImmediateTx(caller: Principal, tx: Tx.Tx): Result<(), ImmediateTxError> =
      // do the same validation that otherwise the aggregator would do
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

    func processTx(tx: Tx.Tx): Result<(), ProcessingError> {
      // Pre-validation has been performed on the aggregator side. We still validate:
      // - owner Id-s
      // - subaccount Id-s
      // - asset type
      // - is balance sufficient

      // cache owner ids per contribution. If some principal is unknown - return error
      let ownersCache: [var OwnerId] = Array.init(tx.map.size(), 0);
      for (j in ownersCache.keys()) {
        switch (owners.get(tx.map[j].owner)) {
          case (null) {
            return #err(#UnknownPrincipal);
          };
          case (?oid) {
            ownersCache[j] := oid;
          };
        };
      };
      // list of new subaccounts to be written after full validation
      var newSubaccounts = List.nil<(OwnerId, SubaccountId, SubaccountState)>();
      var newVirtualAccounts = List.nil<(OwnerId, VirtualAccountId, VirtualAccountState)>();
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
        for ((accountRef, flowAsset, isInflow) in u.iterConcat(
          Iter.map<(AccountReference, Asset), (AccountReference, Asset, Bool)>(contribution.inflow.vals(), func (sid, ast) = (sid, ast, true)),
          Iter.map<(AccountReference, Asset), (AccountReference, Asset, Bool)>(contribution.outflow.vals(), func (sid, ast) = (sid, ast, false)),
        )) {
          switch (accountRef) {
            case (#sub subAccountId) {
              switch (processSubaccountFlow(oid, subAccountId, flowAsset, isInflow)) {
                case (#err err) {
                  return #err(err);
                };
                case (#ok newState) newSubaccounts := List.push((oid, subAccountId, newState), newSubaccounts);
              };
            };
            case (#vir (accountHolder, accountId)) {
              switch (owners.get(accountHolder)) {
                case (null) {
                  return #err(#UnknownPrincipal);
                };
                case (?virOwner) {
                  switch (processVirtualAccountFlow(virOwner, accountId, contribution.owner, flowAsset, isInflow)) {
                    case (#err err) {
                      return #err(err);
                    };
                    case (#ok (newVirtualAccountState, newSubaccountState)) {
                      newVirtualAccounts := List.push((virOwner, accountId, newVirtualAccountState), newVirtualAccounts);
                      newSubaccounts := List.push((virOwner, newVirtualAccountState.backingSubaccountId, newSubaccountState), newSubaccounts);
                    };
                  };
                };
              };
            };
          };
        };
      };
      // pass #2: applying
      for ((oid, subaccountId, newSubaccount) in List.toIter(newSubaccounts)) {
        accounts[oid][subaccountId] := newSubaccount;
      };
      for ((oid, accountId, newVirtualAccount) in List.toIter(newVirtualAccounts)) {
        virtualAccounts[oid][accountId] := ?newVirtualAccount;
      };
      #ok();
    };

    func processSubaccountFlow(ownerId: OwnerId, subaccountId: SubaccountId, flowAsset: Asset, isInflow: Bool): R.Result<SubaccountState, ProcessingError> {
      if (subaccountId >= accounts[ownerId].size()) {
        return #err(#UnknownSubaccount);
      };
      let subaccount = accounts[ownerId][subaccountId];
      switch (processAssetChange(flowAsset, subaccount.asset, isInflow)) {
        case (#ok asset) #ok({ asset = asset });
        case (#err err) #err(err);
      };
    };

    func processVirtualAccountFlow(ownerId: OwnerId, accountId: VirtualAccountId, remotePrincipal: Principal, flowAsset: Asset, isInflow: Bool): R.Result<(VirtualAccountState, SubaccountState), ProcessingError> {
      if (accountId >= virtualAccounts[ownerId].size()) {
        return #err(#UnknownVirtualAccount);
      };
      let account = virtualAccounts[ownerId][accountId];
      switch (account) {
        case (null) return #err(#UnknownVirtualAccount);
        case (?acc) {
          if (acc.remotePrincipal != remotePrincipal) {
            return #err(#MismatchInRemotePrincipal);
          };
          switch (processSubaccountFlow(ownerId, acc.backingSubaccountId, flowAsset, isInflow)) {
            case (#err err) #err(err);
            case (#ok newSubaccountState) {
              switch (processAssetChange(flowAsset, acc.asset, isInflow)) {
                case (#err err) #err(err);
                case (#ok updatedVirtualAsset) {
                  #ok(
                    { 
                      asset = updatedVirtualAsset;
                      backingSubaccountId = acc.backingSubaccountId;
                      remotePrincipal = acc.remotePrincipal;
                    }, 
                    newSubaccountState,
                  );
                };
              };
            };
          };
        };
      };
    };

    func processAssetChange(flowAsset: Asset, userAsset: Asset, isInflow: Bool): Result<Asset, ProcessingError> {
      switch (flowAsset) {
        case (#ft flowAssetData) {
          if (flowAssetData.0 >= counters_.assets) {
            return #err(#UnknownFtAsset);
          };
          switch (userAsset) {
            case (#ft userAssetData) {
              if (flowAssetData.0 != userAssetData.0) {
                return #err(#MismatchInAsset);
              };
              if (isInflow) {
                return #ok(#ft(flowAssetData.0, userAssetData.1 + flowAssetData.1));
              };
              // check is enough balance
              if (userAssetData.1 < flowAssetData.1) {
                return #err(#InsufficientFunds);
              };
              return #ok(#ft(flowAssetData.0, userAssetData.1 - flowAssetData.1));
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

    // The content of all accounts is stored in an array of arrays.
    // The first index is the owner id and the second index is the subaccount id
    // For example, a particular balance in a fungible token is accessed like this:
    //   let #ft(id, balance) = accounts[owner_id][subaccount_id]
    //
    // The outer array is of fixed-length N = constants.maxPrincipals.
    // This means there is space for N different owners and N cannot grow.
    // In the future we will replace this with our own implementation of an array that can grow.
    // The currently available implementations Array and Buffer perform badly in their worst-case
    // when it comes to extending them.
    //
    // When an owner open new subaccounts then we grow that owner's array of subaccounts.
    public let accounts : [var [var SubaccountState]] = Array.init(constants.maxPrincipals, [var] : [var SubaccountState]);
    // virtual accounts
    public let virtualAccounts : [var [var ?VirtualAccountState]] = Array.init(constants.maxPrincipals, [var] : [var ?VirtualAccountState]);

    // history of last processed transactions 
    let batchHistory = CircularBuffer<BatchHistoryEntry>(constants.batchHistoryLength);

    // asset ids
    public var ftControllers: [Principal] = [];

    private var heartbeatsAmount: Nat = 0;
    /** heartbeat function */
    public func heartbeat() : () {
      if (heartbeatsAmount % 60 == 0) {
        tracker.logCanisterStatus();
      };
      heartbeatsAmount += 1;
    };

  };
};
