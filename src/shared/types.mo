module {
  public type AggregatorId = Nat;
  public type SubaccountId = Nat;
  public type AssetId = Nat;

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

  // the amount of transactions in one batch
  public let batchSize = 256;

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
