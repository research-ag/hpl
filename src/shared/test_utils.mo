import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import T "types";
import C "constants";

module {

  public func generateHeavyTx(startPrincipalNumber: Nat): T.Tx =
    {
      map = Array.tabulate<T.Contribution>(
        C.maxContribution,
        func (i: Nat) = {
          owner = principalFromNat(startPrincipalNumber + i);
          inflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j, #ft(0, 10)));
          outflow = Array.tabulate<(T.SubaccountId, T.Asset)>(C.maxFlows / 2, func (j: Nat) = (j + C.maxFlows / 2, #ft(0, 10)));
          memo = ?Blob.fromArray(Array.freeze(Array.init<Nat8>(C.maxMemoSize, 12)));
          autoApprove = false
        },
      );
      committer = null;
    };

  public func principalFromNat(n : Nat) : Principal {
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
}
