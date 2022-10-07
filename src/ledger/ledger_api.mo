import R "mo:base/Result";
import Error "mo:base/Error";
import Ledger "ledger";

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
  public shared({caller}) func openNewAccounts(n: Nat, autoApprove : Bool): async Result<SubaccountId, { #NoSpaceForPrincipal; #NoSpaceForSubaccount }> =
    async ledger_.openNewAccounts(caller, n, autoApprove);

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
  type ProcessingError = Ledger.TxValidationError or { #WrongOwnerId; #WrongSubaccountId; #InsufficientFunds; };
  public shared({caller}) func processBatch(batch: Batch): async () {
    let aggId = u.arrayFindIndex(ledger_.aggregators, func (agg: Principal): Bool = agg == caller);
    switch (aggId) {
      case (#Found index) ledger_.processBatch(index, batch);
      case (#NotFound) throw Error.reject("Not a registered aggregator");
    };
  };

  // queries
  public query func nAggregators(): async Nat = async ledger_.nAggregators();
  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> = async ledger_.aggregatorPrincipal(aid);
  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> = async ledger_.nAccounts(caller);
  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #NotFound; #SubaccountNotFound; }> = async ledger_.asset(caller, sid);

  // admin interface
  // TODO admin-only authorization
  // add one aggregator principal
  public func addAggregator(p : Principal) : async AggregatorId = async ledger_.addAggregator(p);

  // debug interface
  public query func allAssets(owner : Principal) : async Result<[Ledger.SubaccountState], { #NotFound; }> = async ledger_.allAssets(owner);
  public query func counters() : async { nBatchTotal: Nat; nBatchPerAggregator: [Nat]; nTxTotal: Nat; nTxFailed: Nat; nTxSucceeded: Nat } = async ledger_.counters();
  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [Ledger.BatchHistoryEntry] = async ledger_.batchesHistory(startIndex, endIndex);
};
