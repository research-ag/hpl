import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import LedgerAPI "../ledger/ledger_api";
import Tx "../shared/transaction";
import StableMemory "mo:base/ExperimentalStableMemory";


actor class Minter(ledger : Principal) {
    let ledger_ = actor (Principal.toText(ledger)) : LedgerAPI.LedgerAPI;// actor { };
    var assetId_: Nat = 0;

    // stable memory schema:
    // ┏━━━━━━━━┳━━━━━━┳━━━━━━━┓
    // ┃ Offset ┃ Size ┃ Type  ┃ Comment
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ 0      ┃ 1    ┃ Nat8  ┃ size of ledger principal blob
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ 1      ┃ <0>  ┃ Blob  ┃ ledger principalt blob
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ <0>+1  ┃ ?    ┃ Nat64 ┃ asset Id, FIXME we allow asset id number size to be 128 bit, so this will not work
    // ┗━━━━━━━━┻━━━━━━┻━━━━━━━┛
    private func readStableState(): { ledgerPrincipal: Principal; assetId: Tx.AssetId } {
      let ledgerPrincipalBlobSize = Nat8.toNat(StableMemory.loadNat8(0));
      {
        ledgerPrincipal = Principal.fromBlob(StableMemory.loadBlob(1, ledgerPrincipalBlobSize));
        assetId = Nat64.toNat(StableMemory.loadNat64(Nat64.fromNat(1+ledgerPrincipalBlobSize)));
      };
    };
    private func writeStableState(): () {
      let ledgerPrincipalBlob: Blob = Principal.toBlob(ledger);
      let ledgerPrincipalBlobSize: Nat = ledgerPrincipalBlob.size();

      StableMemory.storeNat8(0, Nat8.fromNat(ledgerPrincipalBlob.size()));
      StableMemory.storeBlob(1, ledgerPrincipalBlob);
      StableMemory.storeNat64(Nat64.fromNat(1+ledgerPrincipalBlobSize), Nat64.fromNat(assetId_));
    };

};
