import E "mo:base/ExperimentalInternetComputer";

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Blob "mo:base/Blob";
import R "mo:base/Result";

import Tx "../shared/transaction";
import TestUtils "../shared/test_utils";

import Aggregator "./aggregator";
import LedgerAPI "../ledger/ledger_api";

// aggregator
// the constructor arguments are:
//   principal of the ledger canister
//   own aggregator id
// the constructor arguments are passed like this:
//   dfx deploy --argument='(principal "aaaaa-aa")' aggregator
// alternatively, the argument can be placed in dfx.json according to this scheme:
// https://github.com/dfinity/sdk/blob/ca578a30ea27877a7222176baea3a6aa368ca6e8/docs/dfx-json-schema.json#L222-L229
actor class AggregatorTestAPI(ledger : Principal, ownId : Aggregator.AggregatorId, lookupTableCapacity: Nat) {
  let aggregator_ = Aggregator.Aggregator(ledger, ownId, lookupTableCapacity);

  type Result<X,Y> = R.Result<X,Y>;

  /** Create a new transaction request.
  * Here we init it and put to the lookup table.
  * If the lookup table is full, we try to reuse the slot with oldest unapproved request
  */
  public shared({ caller }) func submit(tx: Tx.Tx): async Result<Aggregator.GlobalId, Aggregator.SubmitError> {
    aggregator_.submit(caller, tx);
  };
  public shared({ caller }) func profileSubmit(tx: Tx.Tx): async (Nat64, Result<Aggregator.GlobalId, Aggregator.SubmitError>) {
    var result: Result<Aggregator.GlobalId, Aggregator.SubmitError> = #err(#NoSpace);
    let instructions: Nat64 = E.countInstructions(func foo() {
      result := aggregator_.submit(caller, tx);
    });
    (instructions, result);
  };
  public shared({ caller }) func submitManySimpleTxs(
    txAmount: Nat, sender: Principal, senderSubaccountId: Tx.SubaccountId, receiver: Principal, receiverSubaccountId: Tx.SubaccountId, amount: Nat
  ): async [Result<Aggregator.GlobalId, Aggregator.SubmitError>] {
    Array.tabulate<Result<Aggregator.GlobalId, Aggregator.SubmitError>>(
      txAmount,
      func (n: Nat) = aggregator_.submit(
        caller,
        createSimpleTx(sender, senderSubaccountId, receiver, receiverSubaccountId, amount)
      )
    );
  };

  /** Approve request. If the caller made the last required approvement, it:
  * - marks request as approved
  * - removes transaction request from the unapproved list
  * - enqueues the request to the batch queue
  */
  public shared({ caller }) func approve(txId: Aggregator.GlobalId): async Result<(), Aggregator.NotPendingError> {
    aggregator_.approve(caller, txId);
  };
  public shared({ caller }) func profileApprove(txId: Aggregator.GlobalId): async (Nat64, Result<(), Aggregator.NotPendingError>) {
    var result: Result<(), Aggregator.NotPendingError> = #err(#AlreadyApproved);
    let instructions: Nat64 = E.countInstructions(func foo() {
      result := aggregator_.approve(caller, txId);
    });
    (instructions, result);
  };

  /** Reject request. It marks request as rejected, but don't remove the request from unapproved list,
  * so it's status can still be queried until overwritten by newer requests
  */
  public shared({ caller }) func reject(txId: Aggregator.GlobalId): async Result<(), Aggregator.NotPendingError> {
    aggregator_.reject(caller, txId);
  };
  public shared({ caller }) func profileReject(txId: Aggregator.GlobalId): async (Nat64, Result<(), Aggregator.NotPendingError>) {
    var result: Result<(), Aggregator.NotPendingError> = #err(#NotFound);
    let instructions: Nat64 = E.countInstructions(func foo() {
      result := aggregator_.reject(caller, txId);
    });
    (instructions, result);
  };

  /** Query transaction request info */
  public query func txDetails(gid: Aggregator.GlobalId): async Result<Aggregator.TxDetails, Aggregator.GidError> {
    aggregator_.txDetails(gid);
  };

  public func getNextBatch() : async Aggregator.Batch {
    Array.map(aggregator_.getNextBatchRequests(), func (req: Aggregator.TxReq): Tx.Tx = req.tx);
  };
  public func profileGetNextBatch() : async (Nat64, Aggregator.Batch) {
    var result: [Aggregator.TxReq] = [];
    let instructions: Nat64 = E.countInstructions(func foo() {
      result := aggregator_.getNextBatchRequests();
    });
    (instructions, Array.map(result, func (req: Aggregator.TxReq): Tx.Tx = req.tx));
  };

  public query func generateSimpleTx(sender: Principal, senderSubaccountId: Tx.SubaccountId, receiver: Principal, receiverSubaccountId: Tx.SubaccountId, amount: Nat): async Tx.Tx {
    createSimpleTx(sender, senderSubaccountId, receiver, receiverSubaccountId, amount);
  };

  public query func generateHeavyTx(startPrincipalNumber: Nat): async Tx.Tx {
    TestUtils.generateHeavyTx(startPrincipalNumber);
  };

  func createSimpleTx(sender: Principal, senderSubaccountId: Tx.SubaccountId, receiver: Principal, receiverSubaccountId: Tx.SubaccountId, amount: Nat): Tx.Tx {
    if (sender == receiver) {
      {
        map = [{
          owner = sender;
          inflow = [ (receiverSubaccountId, #ft(0, amount)) ];
          outflow = [ (senderSubaccountId, #ft(0, amount)) ];
          mints = [];
          burns = [];
          memo = null;
        }];
        committer = null;
      };
    } else {
      {
        map = [{
          owner = sender;
          inflow = [];
          outflow = [ (senderSubaccountId, #ft(0, amount)) ];
          mints = [];
          burns = [];
          memo = null;
        }, {
          owner = receiver;
          inflow = [ (receiverSubaccountId, #ft(0, amount)) ];
          outflow = [];
          mints = [];
          burns = [];
          memo = null;
        }];
        committer = null;
      };
    };
  };

};
