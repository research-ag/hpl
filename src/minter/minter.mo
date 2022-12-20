import Tx "../shared/transaction";
import Ledger "../ledger/ledger";
import R "mo:base/Result";
import Cycles "mo:base/ExperimentalCycles";
import RBTree "mo:base/RBTree";
import Principal "mo:base/Principal";

module {

  public type LedgerInterface = actor {
    createFungibleToken : () -> async R.Result<Tx.AssetId, { #NoSpace; #FeeError }>;
    processImmediateTx : Tx.Tx -> async R.Result<(), Ledger.ImmediateTxError>;
  };

  public type RefundError = { #RefundError; #NothingToRefund };

  public class Minter(ownPrincipal: Principal, ledger: LedgerInterface, asset: Tx.AssetId) {

    public func mint(caller: Principal, p: Principal, n: Tx.SubaccountId): async R.Result<Nat, Ledger.ImmediateTxError> {
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
        case(#err e) {
          addCreditedCycles(caller, amount);
          #err(e);
        };
      };
    };

    public func refundAll(caller: Principal): async R.Result<(), RefundError> {
      let credit = creditTable.get(caller);
      switch(credit) {
        case(?c) {
          Cycles.add(c);
          try {
            let depositResult = await IC.deposit_cycles({ canister_id = caller });
            creditTable.delete(caller);
            #ok();
          } catch (err) {
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

    // Use an actor reference to access the well-known, virtual
    // IC management canister with specified Principal "aaaaa-aa",
    // asserting its interface type
    // NB: this is a smaller supertype of the full interface at
    //     https://sdk.dfinity.org/docs/interface-spec/index.html#ic-management-canister
    let IC =
      actor "aaaaa-aa" : actor {
        create_canister : {
            // richer in ic.did
          } -> async { canister_id : Principal };
        canister_status : { canister_id : Principal } ->
          async { // richer in ic.did
            cycles : Nat
          };
        stop_canister : { canister_id : Principal } -> async ();
        deposit_cycles : { canister_id : Principal } -> async ();
        delete_canister : { canister_id : Principal } -> async ();
      };
    // asset id of minter's currency
    public let assetId = asset;
    // The map from principal to amount of credited cycles:
    let creditTable : RBTree.RBTree<Principal, Nat> = RBTree.RBTree<Principal, Nat>(Principal.compare);

  };

}
