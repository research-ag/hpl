module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;

  public type TransferId = { aid: AggregatorId; tid: Nat };

  public type Asset = { 
    #ft : { id : AssetId; quantity : Nat; }; 
  };

  public type AssetList = [Asset]; 
  // for fungible tokens the above is a map asset id -> quantity
  // asset id must be stricly increasing throughout the list to rule out duplicate keys

  public type Contribution = {
    inflow : [(SubaccountId, AssetList)];
    outflow : [(SubaccountId, AssetList)];
    memo : ?Blob;
    auto_accept : Bool
  };
  // inflow/outflow encodes a map subaccount -> asset list
  // subaccount id must be strictly increasing throughout the list to rule out duplicate keys

  public type Transfer = [(Principal, Contribution)];
  // the above is a map principal -> part
  // principal must be strictly increasing throughout the list to rule out duplicate keys

  public type Batch = [Transfer];
}
