module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;

  public type LocalTxId = Nat;
  public type GlobalTxId = ( aggregator: AggregatorId, local_id: LocalTxId );

  public type Asset = { 
    #ft : (id : AssetId, quantity : Nat); 
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

  public type Transaction = { 
    map : [Contribution]; 
    committer : ?Principal
  };
  // map is seen as a map from a principal to its contribution
  // the principals must be strictly increasing throughout the list to rule out duplicate keys in map

  public type Batch = [Transaction];

  // maximal memo size is 256 bytes
  public let max_memo_size = 256;

  // maximum number of inflows and outflows per contribution
  public let max_flows = 256;

  // maximum number of contributions per transaction
  public let max_contribution = 256;

  // maximum number of subaccounts per principal in ledger
  public let max_subaccounts = 65536; 

  // maximum number of subaccounts total in ledger
  public let max_principals = 65536;
}
