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

  let _ledger = Ledger.Ledger(initialAggregators);

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
  public shared({caller}) func openNewAccounts(n: Nat, autoApprove : Bool): async Result<SubaccountId, { #NoSpace; }> {
    _ledger.openNewAccounts(caller, n, autoApprove);
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
  type ProcessingError = Ledger.TxValidationError or { #WrongOwnerId; #WrongSubaccountId; #InsufficientFunds; };
  public shared({caller}) func processBatch(batch: Batch): async () {
    let aggId = u.arrayFindIndex(_ledger.aggregators, func (agg: Principal): Bool = agg == caller);
    switch (aggId) {
      case (#Found index) _ledger.processBatch(index, batch);
      case (#NotFound) throw Error.reject("Not a registered aggregator");
    };
  };

  // queries

  public query func nAggregators(): async Nat { _ledger.nAggregators(); };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> { _ledger.aggregatorPrincipal(aid); };

  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> { _ledger.nAccounts(caller); };

  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #NotFound; #SubaccountNotFound; }> { _ledger.asset(caller, sid); };

  // admin interface
  // TODO admin-only authorization

  // add one aggregator principal
  public func addAggregator(p : Principal) : async Result<AggregatorId,()> { _ledger.addAggregator(p); };

  // debug interface
  public query func allAssets(owner : Principal) : async Result<[Ledger.SubaccountState], { #NotFound; }> {
    _ledger.allAssets(owner);
  };

  public query func counters() : async { totalBatches: Nat; batchesPerAggregator: [Nat]; totalTxs: Nat; failedTxs: Nat; succeededTxs: Nat } {
    _ledger.counters();
  };

  public query func batchesHistory(startIndex: Nat, endIndex: Nat) : async [Ledger.BatchHistoryEntry] {
    _ledger.batchesHistory(startIndex, endIndex);
  };
};
