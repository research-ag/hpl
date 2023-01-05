import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Array "mo:base/Array";
import R "mo:base/Result";

import Tx "../shared/transaction";
import u "../shared/utils";

module {

  type Result<X,Y> = R.Result<X,Y>;
  type SubaccountId = Tx.SubaccountId;
  type VirtualAccountId = Tx.VirtualAccountId;
  type AccountReference = Tx.AccountReference;
  type Asset = Tx.Asset;
  // copy-paste from ledger.mo
  type OwnerId = Nat;
  type SubaccountState = { asset: Tx.Asset };
  type VirtualAccountState = { asset: Tx.Asset; backingSubaccountId: Tx.SubaccountId; remotePrincipal: Principal };

  type Ledger = {
    virtualAccountState_: (oid : OwnerId, vid: VirtualAccountId) -> Result<VirtualAccountState, { #UnknownVirtualAccount; #DeletedVirtualAccount; }>;
    owners : RBTree.RBTree<Principal, OwnerId>;
    var ftControllers: [Principal];
    accounts : [var [var SubaccountState]];
    virtualAccounts : [var [var ?VirtualAccountState]];
    counters_: { var assets: Nat };
  };
  type BackupStates = { 
    var sub: List.List<(OwnerId, SubaccountId, SubaccountState)>; 
    var vir: List.List<(OwnerId, VirtualAccountId, ?VirtualAccountState)> 
  };
  public type ProcessingError = Tx.TxError or {
    // Errors that start with "Unknown" mean that
    // a value has not yet been registered
    #UnknownPrincipal;
    #UnknownSubaccount;
    #UnknownVirtualAccount;
    #DeletedVirtualAccount;
    #UnknownFtAsset;
    #MismatchInAsset; // asset in flow != asset in account
    #MismatchInRemotePrincipal; // remotePrincipal in flow != remotePrincipal in virtual account
    #InsufficientFunds;
    #NotAController;  // in attempted mint operation
  };

  /** Processes Tx with affecting accounts in ledger */
  public func processTx(ledger: Ledger, tx: Tx.Tx): Result<(), ProcessingError> {
    // Pre-validation has been performed on the aggregator side. We still validate:
    // - owner Id-s
    // - subaccount Id-s
    // - asset type
    // - is balance sufficient

    // list of backup states of modified accounts, if we catch error, those states should be written back to accounts
    let backup: BackupStates = {
      var sub = List.nil<(OwnerId, SubaccountId, SubaccountState)>();
      var vir = List.nil<(OwnerId, VirtualAccountId, ?VirtualAccountState)>();
    };
    var error: ?ProcessingError = null;

    // cache owner ids per contribution for omitting searching it in the tree more than once
    let ownersCache: [var ?OwnerId] = Array.init<?OwnerId>(tx.map.size(), null);
    // loop which validates mint/burns, fills owners cache and processes all inflows
    label applyInflowsLoop
    for (ci in tx.map.keys()) {
      let contrib = tx.map[ci];
      ownersCache[ci] := ledger.owners.get(contrib.owner);
      // mints/burns should be only validated, they do not affect any subaccounts
      for (mintBurnAsset in u.iterConcat(contrib.mints.vals(), contrib.burns.vals())) {
        switch (mintBurnAsset) {
          case (#ft ft) {
            if (contrib.owner != ledger.ftControllers[ft.0]) {
              return #err(#NotAController);
            };
          }
        };
      };
      for ((sid, ast) in contrib.inflow.vals()) {
        switch (processFlow(ledger, backup, contrib.owner, ownersCache[ci], sid, ast, true)) {
          case (#err err) {
            error := ?err;
            break applyInflowsLoop;
          };
          case (#ok) {};
        };
      };
    };
    // process all outflows, if no error was thrown so far
    switch (error) {
      case (null) {
        label applyOutflowsLoop
        for (ci in tx.map.keys()) {
          let contrib = tx.map[ci];
          for ((sid, ast) in contrib.outflow.vals()) {
            switch (processFlow(ledger, backup, contrib.owner, ownersCache[ci], sid, ast, false)) {
              case (#err err) {
                error := ?err;
                break applyOutflowsLoop;
              };
              case (#ok) {};
            };
          };
        };
      };
      case (_) {};
    };

    switch (error) {
      case (?err) { 
        // revert original states. Since we used List.push, next loops will iterate list of backup states in reversed order,
        // so repetitive changes in single account should be handled as expected: the very first state will be applied
        for ((oid, subaccountId, oldState) in List.toIter(backup.sub)) {
          ledger.accounts[oid][subaccountId] := oldState;
        };
        for ((oid, accountId, oldState) in List.toIter(backup.vir)) {
          ledger.virtualAccounts[oid][accountId] := oldState;
        };
        #err(err) 
      };
      case (null) #ok();
    };
  };

  func processFlow(ledger: Ledger, backup: BackupStates, contributionOwner: Principal, ownerId: ?OwnerId, accountRef: AccountReference, flowAsset: Asset, isInflow: Bool): Result<(), ProcessingError> {
    switch (ownerId, accountRef) {
      case (?oid, #sub subAccountId) {
        switch (processSubaccountFlow(ledger, oid, subAccountId, flowAsset, isInflow)) {
          case (#err err) #err(err);
          case (#ok newState) {
            backup.sub := List.push((oid, subAccountId, ledger.accounts[oid][subAccountId]), backup.sub);
            ledger.accounts[oid][subAccountId] := newState;
            #ok();
          };
        };
      };
      case (null, #sub _) #err(#UnknownPrincipal);
      case (_, #vir (accountHolder, accountId)) {
        switch (ledger.owners.get(accountHolder)) {
          case (null) #err(#UnknownPrincipal);
          case (?virOwner) {
            switch (processVirtualAccountFlow(ledger, virOwner, accountId, contributionOwner, flowAsset, isInflow)) {
              case (#err err) #err(err);
              case (#ok (newVirtualAccountState, newSubaccountState)) {
                // write virtual account update
                backup.vir := List.push((
                  virOwner, 
                  accountId, 
                  ledger.virtualAccounts[virOwner][accountId]
                ), backup.vir);
                ledger.virtualAccounts[virOwner][accountId] := ?newVirtualAccountState;
                // write backing subaccount state
                backup.sub := List.push((
                  virOwner, 
                  newVirtualAccountState.backingSubaccountId, 
                  ledger.accounts[virOwner][newVirtualAccountState.backingSubaccountId]
                ), backup.sub);
                ledger.accounts[virOwner][newVirtualAccountState.backingSubaccountId] := newSubaccountState;
                #ok();
              };
            };
          };
        };
      };
    };
  };

  func processSubaccountFlow(ledger: Ledger, ownerId: OwnerId, subaccountId: SubaccountId, flowAsset: Asset, isInflow: Bool): R.Result<SubaccountState, ProcessingError> {
    if (subaccountId >= ledger.accounts[ownerId].size()) {
      return #err(#UnknownSubaccount);
    };
    R.mapOk<Asset, SubaccountState, ProcessingError>(
      processAssetChange(ledger, flowAsset, ledger.accounts[ownerId][subaccountId].asset, isInflow), 
      func (asset) = { asset = asset }
    );
  };

  func processVirtualAccountFlow(ledger: Ledger, ownerId: OwnerId, accountId: VirtualAccountId, remotePrincipal: Principal, flowAsset: Asset, isInflow: Bool): R.Result<(VirtualAccountState, SubaccountState), ProcessingError> {
    switch (ledger.virtualAccountState_(ownerId, accountId)) {
      case (#err err) return #err(err);
      case (#ok acc) {
        if (acc.remotePrincipal != remotePrincipal) {
          return #err(#MismatchInRemotePrincipal);
        };
        switch (processSubaccountFlow(ledger, ownerId, acc.backingSubaccountId, flowAsset, isInflow)) {
          case (#err err) #err(err);
          case (#ok newSubaccountState) {
            R.mapOk<Asset, (VirtualAccountState, SubaccountState), ProcessingError>(
              processAssetChange(ledger, flowAsset, acc.asset, isInflow),
              func (updatedVirtualAsset: Asset) = (
                  { 
                    asset = updatedVirtualAsset;
                    backingSubaccountId = acc.backingSubaccountId;
                    remotePrincipal = acc.remotePrincipal;
                  },
                  newSubaccountState,
              )
            );
          };
        };
      };
    };
  };

  func processAssetChange(ledger: Ledger, flowAsset: Asset, userAsset: Asset, isInflow: Bool): Result<Asset, ProcessingError> {
    switch (flowAsset) {
      case (#ft flowAssetData) {
        if (flowAssetData.0 >= ledger.counters_.assets) {
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
};