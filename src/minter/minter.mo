import Tx "../shared/transaction";
import Ledger "../ledger/ledger";
import R "mo:base/Result";

module {

  public type LedgerInterface = actor {
    createFungibleToken : () -> async R.Result<Tx.AssetId, { #NoSpace; #FeeError }>;
    processImmediateTx : Tx.Tx -> async R.Result<(), Ledger.ImmediateTxError>;
  };

  public class Minter(ownPrincipal: Principal, ledger: LedgerInterface, assetId: Tx.AssetId) {

    public func mint(p: Principal, n: Tx.SubaccountId, tokensAmount: Nat): async R.Result<(), Ledger.ImmediateTxError> {
      await ledger.processImmediateTx({
        map = [
          {
            owner = ownPrincipal;
            mints = [#ft(assetId, tokensAmount)];
            burns = [];
            inflow = [];
            outflow = [];
            memo = null;
          }, {
            owner = p;
            mints = [];
            burns = [];
            inflow = [(n, #ft(assetId, tokensAmount))];
            outflow = [];
            memo = null;
          },
        ]
      })
    };

  };

}
