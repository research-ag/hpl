import HPLTypes "../shared/types";

actor {

  type Balance = Nat;
  type TokenBalance = {
    unit : HPLTypes.TokenId;
    balance : Balance;
  };

  public query func nAggregators(): async Nat {
    // TODO
    return 0
  };

  public query func aggregatorPrincipal(aid: HPLTypes.AggregatorId): async { #principal: Principal; #err: Nat } {
    // TODO
    #err 1;
  };

  public query func nAccounts(): async Nat {
    // TODO
    return 0
  };

  public func openNewAccounts(tid: HPLTypes.TokenId, amount: Nat): async { #subaccountId: HPLTypes.SubaccountId; #err: Nat } {
    // TODO
    #err 1;
  };

  public query func balance(sid: HPLTypes.SubaccountId): async { #tokenBalance: TokenBalance; #err: Nat } {
    // TODO
    #err 1;
  };

  public func processBatch(batch: HPLTypes.Batch): async [{ #transferId: HPLTypes.TransferId; #err: Nat }] {
    // TODO
    return [];
  }

};
