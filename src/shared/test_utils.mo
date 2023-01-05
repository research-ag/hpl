import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Tx "transaction";

module {

  public func generateHeavyTx(startPrincipalNumber: Nat, settings: { appendMemo: Bool; failLastFlow: Bool }): Tx.Tx =
    {
      map = Array.tabulate<Tx.Contribution>(
        Tx.constants.maxContributions,
        func (i: Nat) = {
          owner = principalFromNat(startPrincipalNumber + i);
          inflow = Array.tabulate<(Tx.AccountReference, Tx.Asset)>(Tx.constants.maxFlows / 2, func (j: Nat) = (#sub(j), #ft(0, 10)));
          outflow = Array.tabulate<(Tx.AccountReference, Tx.Asset)>(
            Tx.constants.maxFlows / 2, 
            func (j: Nat) = (
              #sub(j + Tx.constants.maxFlows / 2), 
              #ft(0, if (settings.failLastFlow and j + 1 == Tx.constants.maxFlows / 2 and i + 1 == Tx.constants.maxContributions) 9999999999999 else 10)
            )
          );
          mints = [];
          burns = [];
          memo = if (settings.appendMemo) { ?Blob.fromArray(Array.freeze(Array.init<Nat8>(Tx.constants.maxMemoBytes, 12))) } else { null; };
        },
      );
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
