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

  // maximal memo size is 256 bytes
  public let max_memo_size = 256;

  // maximum number of inflows and outflows per contribution
  public let max_flows = 256;

  // maximum number of contributions per transaction
  public let max_contribution = 256;

  // maximum number of subaccounts per principal in ledger
  public let max_contribution = 2**16;

  // maximum number of subaccount total in ledger
  public let max_principals = 2**24;
}
