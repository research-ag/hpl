import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Ledger "../../src/ledger/main";
import T "../../src/shared/types";
import C "../../src/shared/constants";

actor class LedgerTestUtil(_ledger : Principal) {

  let ledger : Principal = _ledger;
  let Ledger_actor = actor (Principal.toText(ledger)) : Ledger.Ledger;

  public func createTestBatch(committer: Principal, owner: Principal, txAmount: Nat): async [T.Tx] {
    let tx: T.Tx = {
      map = [{ owner = owner; inflow = [(0, #ft(0, 0))]; outflow = [(1, #ft(0, 0))]; memo = null; autoApprove = false }];
      committer = ?committer;
    };
    Array.freeze(Array.init<T.Tx>(txAmount, tx));
  };

  public func registerPrincipals(startPrincipalNumber: Nat, amount: Nat, subaccountsAmount: Nat, autoApprove: Bool): async () {
    let _ = Ledger_actor.bulkOpenSubaccounts(
      Iter.toArray<Principal>(
        Iter.map<Nat, Principal>(
          Iter.range(startPrincipalNumber, startPrincipalNumber + amount),
          func (i: Nat) : Principal = principalFromNat(i)
        )
      ),
      subaccountsAmount,
      autoApprove
    );
  };

  public func generateHeavyTx(startPrincipalNumber: Nat): async T.Tx {
    {
      map = Array.tabulate<T.Contribution>(
        C.maxContribution,
        func (i: Nat) = {
          owner = principalFromNat(startPrincipalNumber + i);
          inflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j, #ft(0, 10)));
          outflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j + C.maxFlows / 2 + 1, #ft(0, 10)));
          memo = ?Blob.fromArray(Array.freeze(Array.init<Nat8>(C.maxMemoSize, 12)));
          autoApprove = false
        },
      );
      committer = null;
    };
  };

  private func principalFromNat(n : Nat) : Principal {
    let blobLength = 16;
    Principal.fromBlob(Blob.fromArray(
      Array.tabulate<Nat8>(
        blobLength,
        func (i : Nat) : Nat8 {
          assert(i < blobLength);
          let shift : Nat = 8 * (blobLength - 1 - i);
          Nat8.fromIntWrap(n / 2**shift)
        }
      )
    ));
};
};
