import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Tx "../shared/transaction";
import StableMemory "mo:base/ExperimentalStableMemory";
import Minter "minter";
import Error "mo:base/Error";
import R "mo:base/Result";
import Ledger "../ledger/ledger";

actor class MinterAPI(ledger : Principal) = self {

  private var minter_: ?Minter.Minter = null;

  public shared func init(): async R.Result<(), { #NoSpace; #FeeError }> {
    switch (minter_) {
      case (?m) #ok();
      case (_) {
        let ledgerActor = actor (Principal.toText(ledger)) : Minter.LedgerInterface;
        let savedState = readStableState();
        if (Principal.equal(ledger, savedState.ledgerPrincipal)) {
          minter_ := ?Minter.Minter(Principal.fromActor(self), ledgerActor, savedState.assetId);
          #ok();
        } else {
          let ftResult = await ledgerActor.createFungibleToken();
          switch(ftResult) {
            case(#ok res) {
              minter_ := ?Minter.Minter(Principal.fromActor(self), ledgerActor, res);
              writeStableState({ ledgerPrincipal = ledger; assetId = res; });
              #ok();
            };
            case(#err e) #err(e);
          };
        };
      };
    };
  };

  public shared query func assetId(): async R.Result<Nat, { #NotInitialized }> {
    switch(minter_) {
      case (?m) #ok(m.assetId);
      case (_) #err(#NotInitialized);
    };
  };

  public shared({caller}) func mint(p: Principal, n: Tx.SubaccountId): async R.Result<Nat, Ledger.ImmediateTxError or { #NotInitialized }> {
    switch(minter_) {
      case (?m) await m.mint(p, n);
      case (_) #err(#NotInitialized);
    };
  };

  public shared({caller}) func refundAll(): async R.Result<(), { #RefundError; #NotInitialized }> {
    switch(minter_) {
      case (?m) await m.refundAll();
      case (_) #err(#NotInitialized);
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
  // ┃ <0>+1  ┃ 4    ┃ Nat32 ┃ asset Id, we allow it to be maximum 24-bit length, so Nat32 is enough
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
