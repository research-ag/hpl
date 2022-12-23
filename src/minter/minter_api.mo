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
  stable var savedArgs : ?(Principal, Nat) = null; // (own principal, asset id)
  stable var stableCreditTable : [(Principal, Nat)] = [];

  var minter = switch (savedArgs) {
    case (?v) ?Minter.Minter(Ledger, v.0, v.1);
    case (_) null
  };

  var initActive = false; // lock to prevent concurrent init() calls

  public shared func init(): async R.Result<Nat, L.CreateFtError or { #CouldNotSend }> {
    assert Option.isNull(savedArgs); // trap if already initialized
    assert (not initActive); // trap if init() already in process
    initActive := true;
    let p = Principal.fromActor(self);
    let ret = try {
      let res = await Ledger.createFungibleToken();
      switch(res) {
        case(#ok aid) {
          savedArgs := ?(p, aid);
          minter := ?Minter.Minter(Ledger, p, aid)
        };
        case(_) {}
      };
      res
    } catch (e) {
      #err(#CouldNotSend)
    };
    initActive := false;
    ret
  };

  public query func assetId(): async ?Nat {
    let toAssetId : ((Principal, Nat)) -> Nat = func x = x.1;
    Option.map(savedArgs, toAssetId);
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
      case(?m) stableCreditTable := m.serializeCreditTable();
      case(_) { };
    };
  };

  system func postupgrade() {
    switch(minter) {
      case(?m) m.deserializeCreditTable(stableCreditTable);
      case(_) { };
    };
  };

};
