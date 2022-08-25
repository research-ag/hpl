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
  type AssetList = T.AssetList;
  type Batch = T.Batch;

  public query func nAggregators(): async Nat {
    nyi();
  };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> {
    nyi();
  };

  public query func nAccounts(): async Nat {
    nyi();
  };

  public func openNewAccounts(amount: Nat): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  public query func assets(sid: SubaccountId): async Result<AssetList, Nat> {
    nyi();
  };

  public func processBatch(batch: Batch): async [{ #transferId: TransferId; #err: Nat }] {
    nyi();
  }

};
