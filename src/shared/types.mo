module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;
  public type TokenId = Nat;

  // transaction ids
  public type LocalId = Nat;
  public type GlobalId = ( aggregator: AggregatorId, local_id: LocalId );

  public type Asset = { 
    #ft : (id : AssetId, quantity : Nat);
    #none;
  };

  public type Contribution = {
    owner : Principal;
    inflow : [(SubaccountId, Asset)];
    outflow : [(SubaccountId, Asset)];
    memo : ?Blob;
    auto_approve : Bool
  };
  // inflow/outflow encodes a map subaccount -> asset list
  // subaccount id must be strictly increasing throughout the list to rule out duplicate keys

  // Tx = Transaction
  // map is seen as a map from a principal to its contribution
  // TODO the principals must be strictly increasing throughout the list to rule out duplicate keys in map
  public type Tx = {
    map : [Contribution];
    committer : ?Principal
  };

  public type Batch = [Tx];
}
