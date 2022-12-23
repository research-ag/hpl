import E "mo:base/ExperimentalInternetComputer";

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Error "mo:base/Error";
import Ledger "ledger";

import Tx "../shared/transaction";
import u "../shared/utils";
import TestUtils "../shared/test_utils";

actor class TestLedgerAPI(initialAggregators : [Principal]) {
  let ledger_ = Ledger.Ledger(initialAggregators);

  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = Ledger.AggregatorId;
  type SubaccountId = Ledger.SubaccountId;
  type Batch = Ledger.Batch;

  // updates
  /*
  Open n new subaccounts.
  */
  public shared({caller}) func openNewAccounts(n: Nat, assetId: Ledger.AssetId): async Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #UnknownFtAsset }> =
    async ledger_.openNewAccounts(caller, n, assetId);

  /*
  Process a batch of transactions. Each transaction only executes if the following conditions are met:
  - all outflow subaccounts have matching token id and sufficient balance
  - all inflow subaccounts have matching token id
  - on a per-token id basis the sum of all outflows matches all inflows
  There is no return value.
  If the call returns (i.e. no system-level failure) the aggregator knows that the batch has been processed.
  If the aggregator catches a system-level failure then it knows that the batch has not been processed.
  */
  public shared({caller}) func processBatch(batch: Batch): async () {
    let aggId = u.arrayFindIndex(ledger_.aggregators, func (agg: Principal): Bool = agg == caller);
    switch (aggId) {
      case (#Found index) ledger_.processBatch(index, batch);
      case (#NotFound) throw Error.reject("Not a registered aggregator");
    };
  };
  public func profile(batch : Batch): async Nat64 = async E.countInstructions(func foo() = ledger_.processBatch(0, batch));

  // queries
  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> = async ledger_.aggregatorPrincipal(aid);
  public shared query ({caller}) func nAccounts(): async Result<Nat, { #UnknownPrincipal; }> = async ledger_.nAccounts(caller);
  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #UnknownPrincipal; #UnknownSubaccount; }> = async ledger_.asset(caller, sid);

  public query func createTestBatch(owner: Principal, txAmount: Nat): async [Tx.Tx] {
    let tx: Tx.Tx = {
      map = [{ owner = owner; inflow = [(0, #ft(0, 0))]; outflow = [(1, #ft(0, 0))]; mints = []; burns = []; memo = null }]
    };
    Array.freeze(Array.init<Tx.Tx>(txAmount, tx));
  };

  public query func generateHeavyTx(startPrincipalNumber: Nat): async Tx.Tx {
    TestUtils.generateHeavyTx(startPrincipalNumber);
  };

  public func registerPrincipals(startPrincipalNumber: Nat, amount: Nat, subaccountsAmount: Nat, initialBalance: Nat): async () {
    let initialAsset = { asset = #ft(0, initialBalance) };
    for (p in Iter.map<Nat, Principal>(Iter.range(startPrincipalNumber, startPrincipalNumber + amount), func (i: Nat) : Principal = TestUtils.principalFromNat(i))) {
      switch (ledger_.getOrCreateOwnerId(p)) {
        case (null) ();
        case (?oid) ledger_.accounts[oid] := Array.init<Ledger.SubaccountState>(subaccountsAmount, initialAsset);
      };
    };
  };
  // admin interface
  // TODO admin-only authorization
  // add one aggregator principal
  public func addAggregator(p : Principal) : async AggregatorId = async ledger_.addAggregator(p);

  // TODO: the following function checks if principal exists but not if subaccount exists
  // TODO: can the following function run a mint transaction instead? 
  public func issueTokens(userPrincipal: Principal, subaccountId: SubaccountId, asset: Ledger.Asset) : async Result<Ledger.SubaccountState,Ledger.ProcessingError> {
    switch (ledger_.ownerId(userPrincipal)) {
      case (#err _) #err(#UnknownPrincipal);
      case (#ok oid) {
        ledger_.accounts[oid][subaccountId] := { asset = asset };
        #ok(ledger_.accounts[oid][subaccountId]);
      };
    };
  };

  public shared ({caller}) func createFungibleToken() : async Result<Ledger.AssetId, Ledger.CreateFtError> {
    ledger_.createFungibleToken(caller);
  };

  // debug interface
  public query func allAssets(owner : Principal) : async Result<[Ledger.SubaccountState], { #UnknownPrincipal }> = async ledger_.allAssets(owner);
  public query func stats() : async Ledger.Stats = async ledger_.stats();
  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [Ledger.BatchHistoryEntry] = async ledger_.batchesHistory(startIndex, endIndex);

};
