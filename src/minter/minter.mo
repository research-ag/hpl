import Tx "../shared/transaction";
import Ledger "../ledger/ledger";
import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";
import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";

module {

  public type LedgerInterface = actor {
    createFungibleToken : () -> async R.Result<Tx.AssetId, { #NoSpace; #FeeError }>;
    processImmediateTx : Tx.Tx -> async R.Result<(), Ledger.ImmediateTxError>;
  };

  public type RefundError = { #RefundError; #NothingToRefund };

  public type MintError = Ledger.ImmediateTxError or { #CallLedgerError };

  public class Minter(ownPrincipal: Principal, ledger: LedgerInterface, assetId: Tx.AssetId) {

    public func mint(caller: Principal, p: Principal, n: Tx.SubaccountId): async R.Result<Nat, MintError> {
      // accept cycles
      let amount = Cycles.available();
      assert(amount > 0);
      let accepted = Cycles.accept(amount);
      assert(accepted == amount);
      // mint tokens
      let tokensAmount = accepted;
      try {
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
          case(#err e) {
            addCreditedCycles(caller, amount);
            #err(e);
          };
        };
      } catch (err) {
        addCreditedCycles(caller, amount);
        #err(#CallLedgerError);
      }
    };

    public func refundAll(caller: Principal): async R.Result<(), RefundError> {
      let credit = creditTable.get(caller);
      switch(credit) {
        case(?c) {
          Cycles.add(c);
          creditTable.delete(caller);
          try {
            let depositResult = await IC.deposit_cycles({ canister_id = caller });
            #ok();
          } catch (err) {
            addCreditedCycles(caller, c);
            #err(#RefundError);
          };
        };
        case(_) #err(#NothingToRefund);
      };
    };

    private func addCreditedCycles(caller: Principal, amount: Nat): () {
      let credit = creditTable.get(caller);
      switch(credit) {
        case(?c) creditTable.put(caller, c + amount);
        case(_) creditTable.put(caller, amount);
      };
    };

    // virtual canister for transfering cycles
    let IC =
      actor "aaaaa-aa" : actor {
        deposit_cycles : { canister_id : Principal } -> async ();
      };

    // The map from principal to amount of credited cycles:
    var creditTable : RBTree.RBTree<Principal, Nat> = RBTree.RBTree<Principal, Nat>(Principal.compare);

    public func serializeCreditTable(): [(Principal, Nat)] = Iter.toArray(creditTable.entries());
    public func deserializeCreditTable(values: [(Principal, Nat)]) {
      creditTable := RBTree.RBTree<Principal, Nat>(Principal.compare);
      for ((p, value) in values.vals()) {
        creditTable.put(p, value);
      };
    };
  };

}
