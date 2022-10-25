import E "mo:base/ExperimentalInternetComputer";

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Error "mo:base/Error";
import Ledger "ledger";

import C "../shared/constants";
import T "../shared/types";
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

  Note that the owner does not specify a token id. The new subaccounts hold the Asset value none.
  The token id of a subaccount is determined by the first inflow.
  After that, the token id cannot be changed anymore with the current API.
  For any subsequent transaction the inflow has to match the token id of the subaccount or else is rejected.

  If the owner wants to set a subaccount's token id before the first inflow then the owner can make a transaction that has no inflows and an outflow of the token id and amount 0.
  That will set the Asset value in the subaccount to the wanted token id.
  */
  public shared({caller}) func openNewAccounts(n: Nat, assetId: Ledger.AssetId): async Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount; #WrongAssetId }> =
    async ledger_.openNewAccounts(caller, n, assetId);

  /*
  Process a batch of transactions. Each transaction only executes if the following conditions are met:
  - all outflow subaccounts have matching token id and sufficient balance
  - all inflow subaccounts have matching token id (or Asset value `none`)
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
  public query func nAggregators(): async Nat = async ledger_.nAggregators();
  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> = async ledger_.aggregatorPrincipal(aid);
  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> = async ledger_.nAccounts(caller);
  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #NotFound; #SubaccountNotFound; }> = async ledger_.asset(caller, sid);

  public query func createTestBatch(committer: Principal, owner: Principal, txAmount: Nat): async [T.Tx] {
    let tx: T.Tx = {
      map = [{ owner = owner; inflow = [(0, #ft(0, 0))]; outflow = [(1, #ft(0, 0))]; memo = null }];
      committer = ?committer;
    };
    Array.freeze(Array.init<T.Tx>(txAmount, tx));
  };

  public query func generateHeavyTx(startPrincipalNumber: Nat): async T.Tx {
    TestUtils.generateHeavyTx(startPrincipalNumber);
  };

  public func registerPrincipals(startPrincipalNumber: Nat, amount: Nat, subaccountsAmount: Nat, initialBalance: Nat): async () {
    let initialAsset = { asset = #ft(0, initialBalance) };
    for (p in Iter.map<Nat, Principal>(Iter.range(startPrincipalNumber, startPrincipalNumber + amount), func (i: Nat) : Principal = TestUtils.principalFromNat(i))) {
      switch (ledger_.getOwnerId(p, true)) {
        case (#err _) ();
        case (#ok oid) ledger_.accounts[oid] := Array.init<Ledger.SubaccountState>(subaccountsAmount, initialAsset);
      };
    };
  };
  // admin interface
  // TODO admin-only authorization
  // add one aggregator principal
  public func addAggregator(p : Principal) : async AggregatorId = async ledger_.addAggregator(p);

  public func issueTokens(userPrincipal: Principal, subaccountId: SubaccountId, asset: Ledger.Asset) : async Result<Ledger.SubaccountState,Ledger.ProcessingError> {
    switch (ledger_.ownerId(userPrincipal)) {
      case (#err _) #err(#WrongOwnerId);
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
  public query func allAssets(owner : Principal) : async Result<[Ledger.SubaccountState], { #NotFound; }> = async ledger_.allAssets(owner);
  public query func counters() : async { nBatchTotal: Nat; nBatchPerAggregator: [Nat]; nTxTotal: Nat; nTxFailed: Nat; nTxSucceeded: Nat } = async ledger_.counters();
  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [Ledger.BatchHistoryEntry] = async ledger_.batchesHistory(startIndex, endIndex);

};
