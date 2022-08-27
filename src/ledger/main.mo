import { nyi } "mo:base/Prelude";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// ledger
actor {
  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type TransactionId = T.TransactionId;
  type Asset = T.Asset;
  type Batch = T.Batch;

  // updates

  public func openNewAccounts(amount: Nat): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  public func processBatch(batch: Batch): async [{ #transactionId: TransactionId; #err: Nat }] {
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
