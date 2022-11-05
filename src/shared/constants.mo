module {
  // the number of transactions in one batch
  public let maxBatchRequests = 256;

  // the size of a batch in bytes
  // 2MB - 70 bytes for DIDL prefix and type table
  public let maxBatchBytes = 262074;

  // maximal memo size is 256 bytes
  public let maxMemoSize = 256;

  // maximum number of inflows and outflows per contribution
  public let maxFlows = 256;

  // maximum number of contributions per transaction
  public let maxContribution = 256;

  // maximum quantity of #ft in the flow, equals to 2**128 - 1
  public let flowMaxFtQuantity = 340282366920938463463374607431768211455;

  // maximum number of subaccounts per principal in ledger
  public let maxSubaccounts = 65536;

  // maximum number of accounts total in ledger
  public let maxPrincipals = 16777216;

  // maximum number of stored latest processed batches on the ledger
  public let batchHistoryLength = 1024;

  // maximum number of asset ids total in ledger
  public let maxAssetIds = 16777216;
}
