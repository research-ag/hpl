import R "mo:base/Result";
import Error "mo:base/Error";
import Ledger "ledger";
import Tx "../shared/transaction";
import u "../shared/utils";

// ledger
// the constructor arguments are:
//   initial list of the canister ids of the aggregators
// more can be added later with addAggregator()
// the constructor arguments are passed like this:
//   dfx deploy --argument='(vec { principal "aaaaa-aa"; ... })' ledger
actor class LedgerAPI(initialAggregators : [Principal]) {
  let ledger_ = Ledger.Ledger(initialAggregators);

  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = Ledger.AggregatorId;
  type SubaccountId = Ledger.SubaccountId;
  type Batch = Ledger.Batch;
  type Asset = Ledger.Asset;
  type AssetId = Ledger.AssetId;

  // updates
  /*
  Open n new subaccounts.

  The token id cannot be changed anymore with the current API.
  For any transaction the inflow has to match the token id of the subaccount or else is rejected.

  If the owner wants to set a subaccount's token id before the first inflow then the owner can make a transaction that has no inflows and an outflow of the token id and amount 0.
  That will set the Asset value in the subaccount to the wanted token id.
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

  /*
  Process one Tx immediately. Works only for Tx with single contribution, owned by caller
  */
  public shared({caller}) func processImmediateTx(tx: Tx.Tx): async Result<(), Ledger.ImmediateTxError> = async ledger_.processImmediateTx(caller, tx);

  // asset interface
  // create a new fungible token and get the asset id
  // in the future, calling this will cost a fee in ICP or cycles
  // an error occurs when the maximum number of asset ids is reached
  // an error occurs when the call does not carry a valid fee payment
  // the caller will become the "controller" of the asset id
  // the controller is the sole principal that can mint and burn tokens
  // typically the controller will be a canister
  public shared ({caller}) func createFungibleToken() : async Result<Ledger.AssetId, Ledger.CreateFtError> {
    ledger_.createFungibleToken(caller);
  };

  // queries
  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> = async ledger_.aggregatorPrincipal(aid);
  public shared query ({caller}) func nAccounts(): async Result<Nat, { #UnknownPrincipal; }> = async ledger_.nAccounts(caller);
  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #UnknownPrincipal; #SubaccountNotFound; }> = async ledger_.asset(caller, sid);

  // admin interface
  // TODO admin-only authorization
  // add one aggregator principal
  public func addAggregator(p : Principal) : async AggregatorId = async ledger_.addAggregator(p);

  // debug interface
  public query func allAssets(owner : Principal) : async Result<[Ledger.SubaccountState], { #UnknownPrincipal }> = async ledger_.allAssets(owner);
  public query func stats() : async Ledger.Stats = async ledger_.stats();
  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [Ledger.BatchHistoryEntry] = async ledger_.batchesHistory(startIndex, endIndex);

  /** heartbeat function */
  system func heartbeat() : async () = async ledger_.heartbeat();
};
