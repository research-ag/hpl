import { nyi } "mo:base/Prelude";

// import types (pattern matching not available)
import T "../shared/types";
import R "mo:base/Result";

// ledger
actor {
  // imported types (pattern matching not available)
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type TransferId = T.TransferId;
  type Asset = T.Asset;
  type Batch = T.Batch;

  // updates

  public func openNewAccounts(amount: Nat): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  public func processBatch(batch: Batch): async [{ #transferId: TransferId; #err: Nat }] {
    nyi();
  };

  // queries

  public query func nAggregators(): async Nat {
    nyi();
  };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> {
    nyi();
  };

  public query func nAccounts(): async Result<Nat, { #NotFound; }> {
    nyi();
  };

  public query func asset(sid: SubaccountId): async Result<Asset, { #NotFound; #SubaccountNotFound; }> {
    nyi();
  };

  // debug interface

  public query func all_assets(owner : Principal) : async Result<[Asset], { #NotFound; }> {
    nyi();
  };
};
