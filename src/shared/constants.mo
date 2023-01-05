// constants that are shared by transaction.mo and ledger.mo
module {
  // maximum number of subaccounts per principal
  public let maxSubaccounts = 65536;

  // maximum number of virtual accounts per principal
  public let maxVirtualAccounts = 65536;

  // maximum number of asset ids
  public let maxAssets = 16777216;
}