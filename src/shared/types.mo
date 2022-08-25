import Prelude "mo:base/Prelude";

module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;

  public type TransferId = { aid: AggregatorId; tid: Nat };
  public type Asset = { 
    #ft : { id : AssetId; quantity : Nat; }; 
  };
  public type Flow = { #inc: Asset; #dec : Asset };
  public type Part = {
    owner : Principal;
    flows : [Flow];
    memo : ?Blob
  };
  public type Transfer = [Part];
  public type Batch = [Transfer];

  public func a(): () {}; 
  public func b(): () {}; 
}
