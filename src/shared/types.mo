module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type TokenId = Nat;

  public type TransferId = { aid: AggregatorId; tid: Nat };
  public type Flow = {
    token : TokenId;
    subaccount : Nat;
    amount : Int;
  };
  public type Part = {
    owner : Principal;
    flows : [Flow];
    memo : ?Blob
  };
  public type Transfer = [Part];
  public type Batch = [Transfer];
}
