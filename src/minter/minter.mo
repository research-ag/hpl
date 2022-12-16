import Tx "../shared/transaction";
import Ledger "../ledger/ledger";
import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";

module {

  public type LedgerInterface = actor {
    createFungibleToken : () -> async R.Result<Tx.AssetId, { #NoSpace; #FeeError }>;
    processImmediateTx : Tx.Tx -> async R.Result<(), Ledger.ImmediateTxError>;
  };

  public class Minter(ownPrincipal: Principal, ledger: LedgerInterface, asset: Tx.AssetId) {

    public let assetId = asset;

    public func mint(p: Principal, n: Tx.SubaccountId): async R.Result<Nat, Ledger.ImmediateTxError> {
      // accept cycles
      let amount = Cycles.available();
      assert(amount > 0);
      let accepted = Cycles.accept(amount);
      assert(accepted == amount);
      // mint tokens
      let tokensAmount = accepted;
      let mintResult = await ledger.processImmediateTx({
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
      });
      switch(mintResult) {
        case(#ok _) #ok(tokensAmount);
        case(#err e) #err(e);
      };
    };

    public func refundAll(): async R.Result<(), {#RefundError}> {
      // TODO
      #ok();
    };

  };

}
