import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import R "mo:base/Result";

import Minter "minter";
import L "../ledger/ledger";
import Tx "../shared/transaction";

actor class MinterAPI(ledger : ?Principal) = self {

  stable let Ledger = switch (ledger) {
    case (?p) actor (Principal.toText(p)) : Minter.LedgerInterface; 
    case (_) { Debug.trap("not initialized and no ledger supplied");}
  };
  stable var saved : ?(Principal, Nat) = null; // (own principal, asset id)
  stable var creditTable : [(Principal, Nat)] = [];

  var minter = switch (saved) {
    case (?v) ?Minter.Minter(v.0, Ledger, v.1);
    case (_) null
  };

  var initActive = false;
  public shared func init(): async R.Result<Nat, L.CreateFtError> {
    // trap if values are already initialized
    assert Option.isNull(saved);
    // trap if creation of asset id is already under way
    assert (not initActive);
    initActive := true;
    let res = await Ledger.createFungibleToken();
    switch(res) {
      case(#ok id) {
        let p = Principal.fromActor(self);
        saved := ?(p, id);
        minter := ?Minter.Minter(p, Ledger, id)
      };
      case(_) {}
    };
    initActive := false;
    res
  };

  public query func assetId(): async ?Nat {
    // let id : (Principal, Nat) -> Nat = func (x) { x.1 };
    let id = func (x : (Principal, Nat)) : Nat { x.1 };
    Option.map(saved, id);
  };
  public query func ledgerPrincipal(): async Principal = async Principal.fromActor(Ledger);

  public shared({caller}) func mint(p: Principal, n: Tx.SubaccountId): async R.Result<Nat, Minter.MintError> {
    switch(minter) {
      case (?m) await m.mint(caller, p, n);
      case (_) Debug.trap("not initialized");
    };
  };

  public shared({caller}) func refundAll(): async R.Result<(), Minter.RefundError> {
    switch(minter) {
      case (?m) await m.refundAll(caller);
      case (_) Debug.trap("not initialized");
    };
  };

  system func preupgrade() {
    switch(minter) {
      case(?m) creditTable := m.serializeCreditTable();
      case(_) { };
    };
  };

  system func postupgrade() {
    switch(minter) {
      case(?m) m.deserializeCreditTable(creditTable);
      case(_) { };
    };
  };

};
