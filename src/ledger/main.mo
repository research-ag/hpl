import HPLTypes "../shared/types";
import Prelude "mo:base/Prelude";

actor {

  type Balance = Nat;
  type TokenBalance = {
    unit : HPLTypes.TokenId;
    balance : Balance;
  };

  public query func nAggregators(): async Nat {
    Prelude.nyi();
  };

  public query func aggregatorPrincipal(aid: HPLTypes.AggregatorId): async { #principal: Principal; #err: Nat } {
    Prelude.nyi();
  };

  public query func nAccounts(): async Nat {
    Prelude.nyi();
  };

  public func openNewAccounts(tid: HPLTypes.TokenId, amount: Nat): async { #subaccountId: HPLTypes.SubaccountId; #err: Nat } {
    Prelude.nyi();
  };

  public query func balance(sid: HPLTypes.SubaccountId): async { #tokenBalance: TokenBalance; #err: Nat } {
    Prelude.nyi();
  };

  public func processBatch(batch: HPLTypes.Batch): async [{ #transferId: HPLTypes.TransferId; #err: Nat }] {
    Prelude.nyi();
  }

};
