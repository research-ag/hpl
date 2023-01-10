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
  public type BurnError = Ledger.ImmediateTxError or { #DepositCyclesError; #CallLedgerError };

  public class Minter(ledger: LedgerInterface, ownPrincipal: Principal, assetId: Tx.AssetId) {

    public func mint(caller: Principal, accountOwner: Principal, accountId: Tx.VirtualAccountId): async* R.Result<Nat, MintError> {
      // accept cycles
      let amount = Cycles.available();
      assert(amount > 0);
      let tokensAmount = Cycles.accept(amount);
      assert(tokensAmount == amount);
      // mint tokens
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
              owner = ownPrincipal;
              mints = [];
              burns = [];
              inflow = [(#vir(accountOwner, accountId), #ft(assetId, tokensAmount))];
              outflow = [];
              memo = null;
            },
          ]
        });
        switch(mintResult) {
          case(#ok _) #ok(tokensAmount);
          case(#err e) {
            addCreditedCycles(caller, tokensAmount);
            #err(e);
          };
        };
      } catch (err) {
        addCreditedCycles(caller, tokensAmount);
        #err(#CallLedgerError);
      }
    };

    public func burn(caller: Principal, accountId: Tx.VirtualAccountId, amount: Nat, depositDestination: Principal): async* R.Result<Nat, BurnError> {
      let burnResult = try {
        await ledger.processImmediateTx({
          map = [
            {
              owner = ownPrincipal;
              mints = [];
              burns = [#ft(assetId, amount)];
              inflow = [];
              outflow = [];
              memo = null;
            }, {
              owner = ownPrincipal;
              mints = [];
              burns = [];
              inflow = [];
              outflow = [(#vir(caller, accountId), #ft(assetId, amount))];
              memo = null;
            },
          ]
        });
      } catch (err) {
        #err(#CallLedgerError);
      };
      switch(burnResult) {
        case(#ok _) 
          try {
            await* sendCyclesTo(depositDestination, amount);
            #ok(amount);
          } catch (err) {
            addCreditedCycles(caller, amount);
            #err(#DepositCyclesError);
          };
        case(#err e) #err(e);
      };
    };

    // FIXME will trap if total credit exceeds 2^128 cycles
    public func refundAll(caller: Principal): async* R.Result<(), RefundError> {
      let credit = creditTable.get(caller);
      switch(credit) {
        case(?c) {
          creditTable.delete(caller);
          try {
            await* sendCyclesTo(caller, c);
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

    private func sendCyclesTo(target: Principal, amount: Nat): async* () {
      Cycles.add(amount);
      await IC.deposit_cycles({ canister_id = target });
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
