module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;

  public type TransactionId = { aid: AggregatorId; tid: Nat };

  public type Asset = { 
    #ft : (id : AssetId, quantity : Nat); 
  };

  public type Contribution = {
    inflow : [(SubaccountId, Asset)];
    outflow : [(SubaccountId, Asset)];
    memo : ?Blob;
    auto_approve : Bool
  };
  // inflow/outflow encodes a map subaccount -> asset list
  // subaccount id must be strictly increasing throughout the list to rule out duplicate keys

  public type Transaction = { 
    map : [(Principal, Contribution)]; 
    committer : ?Principal
  };
  // principal must be strictly increasing throughout the list to rule out duplicate keys in map

  public type Batch = [Transaction];
}
