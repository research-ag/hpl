import LedgerAPI "../ledger/ledger_api";
import Tx "../shared/transaction";

class Minter(ledger: LedgerAPI.LedgerAPI, assetId: Tx.AssetId) {
  func mint(): () {};
};
