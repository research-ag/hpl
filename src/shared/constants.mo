module {
  // the amount of transactions in one batch
  public let batchSize = 256;

  // maximal memo size is 256 bytes
  public let maxMemoSize = 256;

  // maximum number of inflows and outflows per contribution
  public let maxFlows = 256;

  // maximum number of contributions per transaction
  public let maxContribution = 256;

  // maximum number of subaccounts per principal in ledger
  public let maxSubaccounts = 65536;

  // maximum number of accounts total in ledger
  public let maxPrincipals = 16777216;

  // maximum number of stored latest processed batches on the ledger
  public let batchHistoryLength = 1024;

  // maximum number of asset ids total in ledger
  public let maxAssetIds = 16777216;
}
