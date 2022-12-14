import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import LedgerAPI "../ledger/ledger_api";
import Tx "../shared/transaction";
import StableMemory "mo:base/ExperimentalStableMemory";
import Minter "minter";
import Error "mo:base/Error";

actor class MinterAPI(ledger : Principal) {

    private var minter_: ?Minter.Minter = null;
    private func getMinter(): async Minter.Minter {
      switch (minter_) {
        case (?m) m;
        case (_) {
          let ledgerActor = actor (Principal.toText(ledger)) : LedgerAPI.LedgerAPI;// actor { };
          let savedState = readStableState();
          if (Principal.equal(ledger, savedState.ledgerPrincipal)) {
            let m = Minter.Minter(ledgerActor, savedState.assetId);
            minter_ := ?m;
            return m;
          } else {
            let ftResult = await ledgerActor.createFungibleToken();
            switch(ftResult) {
              case(#ok res) {
                let m = Minter.Minter(ledgerActor, res);
                minter_ := ?m;
                writeStableState({ ledgerPrincipal = ledger; assetId = res; });
                return m;
              };
              case(_) {
                // FIXME handle error
                throw Error.reject("Minter not initialized!");
              };
            };
          };
        };
      };
    };

    // stable memory schema:
    // ┏━━━━━━━━┳━━━━━━┳━━━━━━━┓
    // ┃ Offset ┃ Size ┃ Type  ┃ Comment
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ 0      ┃ 1    ┃ Nat8  ┃ size of ledger principal blob
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ 1      ┃ <0>  ┃ Blob  ┃ ledger principal blob
    // ┣━━━━━━━━╋━━━━━━╋━━━━━━━┫
    // ┃ <0>+1  ┃ ?    ┃ Nat32 ┃ asset Id, we allow it to be maximum 24-bit length, so Nat32 is enough
    // ┗━━━━━━━━┻━━━━━━┻━━━━━━━┛
    type StableState = { ledgerPrincipal: Principal; assetId: Tx.AssetId };
    private func readStableState(): StableState {
      let ledgerPrincipalBlobSize = Nat8.toNat(StableMemory.loadNat8(0));
      {
        ledgerPrincipal = Principal.fromBlob(StableMemory.loadBlob(1, ledgerPrincipalBlobSize));
        assetId = Nat32.toNat(StableMemory.loadNat32(Nat64.fromNat(1+ledgerPrincipalBlobSize)));
      };
    };
    private func writeStableState(state: StableState): () {
      let ledgerPrincipalBlob: Blob = Principal.toBlob(state.ledgerPrincipal);
      let ledgerPrincipalBlobSize: Nat = ledgerPrincipalBlob.size();

      StableMemory.storeNat8(0, Nat8.fromNat(ledgerPrincipalBlob.size()));
      StableMemory.storeBlob(1, ledgerPrincipalBlob);
      StableMemory.storeNat32(Nat64.fromNat(1+ledgerPrincipalBlobSize), Nat32.fromNat(state.assetId));
    };

};
