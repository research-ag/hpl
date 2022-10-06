import E "mo:base/ExperimentalInternetComputer";

import RBTree "mo:base/RBTree";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import R "mo:base/Result";
import Error "mo:base/Error";
import Ledger "ledger";

// type imports
// pattern matching is not available for types during import (work-around required)
import T "../shared/types";
import C "../shared/constants";
import v "../shared/validators";
import u "../shared/utils";
import DLL "../shared/dll";
import CircularBuffer "../shared/circular_buffer";
// import LinkedListSet "../shared/linked_list_set";

// ledger
// the constructor arguments are:
//   initial list of the canister ids of the aggregators
// more can be added later with addAggregator()
// the constructor arguments are passed like this:
//   dfx deploy --argument='(vec { principal "aaaaa-aa"; ... })' ledger
actor class TestLedgerAPI(initialAggregators : [Principal]) {

  let _ledger = Ledger.Ledger(initialAggregators);

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type GlobalId = T.GlobalId;
  type AssetId = T.AssetId;
  type Asset = T.Asset;
  type Batch = T.Batch;

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
  type ProcessingError = v.TxValidationError or { #WrongOwnerId; #WrongSubaccountId; #InsufficientFunds; };
  public shared({caller}) func processBatch(batch: Batch): async () {
    let aggId = u.arrayFindIndex(_ledger.aggregators, func (agg: Principal): Bool = agg == caller);
    switch (aggId) {
      case (#Found index) _ledger.processBatch(index, batch);
      case (#NotFound) throw Error.reject("Not a registered aggregator");
    };
  };
  public func profile(batch : Batch): async Nat64 {
    _ledger.profileBatch(batch);
  };

  // queries

  public query func nAggregators(): async Nat { _ledger.nAggregators(); };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> { _ledger.aggregatorPrincipal(aid); };

  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> { _ledger.nAccounts(caller); };

  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Ledger.SubaccountState, { #NotFound; #SubaccountNotFound; }> { _ledger.asset(caller, sid); };

  public query func createTestBatch(committer: Principal, owner: Principal, txAmount: Nat): async [T.Tx] {
    let tx: T.Tx = {
      map = [{ owner = owner; inflow = [(0, #ft(0, 0))]; outflow = [(1, #ft(0, 0))]; memo = null; autoApprove = false }];
      committer = ?committer;
    };
    Array.freeze(Array.init<T.Tx>(txAmount, tx));
  };

  public query func generateHeavyTx(startPrincipalNumber: Nat): async T.Tx {
    {
      map = Array.tabulate<T.Contribution>(
        C.maxContribution,
        func (i: Nat) = {
          owner = principalFromNat(startPrincipalNumber + i);
          inflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j, #ft(0, 10)));
          outflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j + C.maxFlows / 2, #ft(0, 10)));
          memo = ?Blob.fromArray(Array.freeze(Array.init<Nat8>(C.maxMemoSize, 12)));
          autoApprove = false
        },
      );
      committer = null;
    };
  };

  public func registerPrincipals(startPrincipalNumber: Nat, amount: Nat, subaccountsAmount: Nat, autoApprove: Bool, initialBalance: Nat): async () {
    let initialAsset = { asset = #ft(0, initialBalance); autoApprove = autoApprove };
    for (p in Iter.map<Nat, Principal>(Iter.range(startPrincipalNumber, startPrincipalNumber + amount), func (i: Nat) : Principal = principalFromNat(i))) {
      switch (_ledger.registerOrSignPrincipal(p)) {
        case (#err _) ();
        case (#ok oid) _ledger.accounts[oid] := Array.init<Ledger.SubaccountState>(subaccountsAmount, initialAsset);
      };
    };
  };

  // admin interface
  // TODO admin-only authorization

  // add one aggregator principal
  public func addAggregator(p : Principal) : async Result<AggregatorId,()> { _ledger.addAggregator(p); };

  public func issueTokens(userPrincipal: Principal, subaccountId: SubaccountId, asset: Asset) : async Result<Ledger.SubaccountState,ProcessingError> {
    _ledger.issueTokens(userPrincipal, subaccountId, asset);
  };

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

  private func principalFromNat(n : Nat) : Principal {
    let blobLength = 16;
    Principal.fromBlob(Blob.fromArray(
      Array.tabulate<Nat8>(
        blobLength,
        func (i : Nat) : Nat8 {
          assert(i < blobLength);
          let shift : Nat = 8 * (blobLength - 1 - i);
          Nat8.fromIntWrap(n / 2**shift)
        }
      )
    ));
  };
};
