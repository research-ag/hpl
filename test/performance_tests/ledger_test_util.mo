import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Ledger "../../src/ledger/main";
import T "../../src/shared/types";

actor class LedgerTestUtil(_ledger : Principal) {

  let ledger : Principal = _ledger;
  let Ledger_actor = actor (Principal.toText(ledger)) : Ledger.Ledger;

  public shared(msg) func createTestBatch(committer: Principal, owner: Principal, txAmount: Nat): async [T.Tx] {
    let tx: T.Tx = {
      map = [{ owner = owner; inflow = [(0, #ft(0, 0))]; outflow = [(1, #ft(0, 0))]; memo = null; autoApprove = false }];
      committer = ?committer;
    };
    Array.tabulate<T.Tx>(txAmount, func (n) = tx);
  };
};
