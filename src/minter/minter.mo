import Tx "../shared/transaction";
import Ledger "../ledger/ledger";
import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";

module {

  public type LedgerInterface = actor {
    createFungibleToken : () -> async R.Result<Tx.AssetId, { #NoSpace; #FeeError }>;
    processImmediateTx : Tx.Tx -> async R.Result<(), Ledger.ImmediateTxError>;
  };

  public class Minter(ownPrincipal: Principal, ledger: LedgerInterface, assetId: Tx.AssetId) {

    public func mint(p: Principal, n: Tx.SubaccountId): async R.Result<Nat, Ledger.ImmediateTxError> {
      let receivedCycles = Cycles.available();
      ignore Cycles.accept(receivedCycles);
      let tokensAmount = receivedCycles;
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

    public func refundAll(): async R.Result<(), ()> {
      // TODO
      #ok();
    };

  };

}
