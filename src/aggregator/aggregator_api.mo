import Principal "mo:base/Principal";
import Aggregator "./aggregator";
import LedgerAPI "../ledger/ledger_api";
import R "mo:base/Result";
import Tx "../shared/transaction";

// aggregator
// the constructor arguments are:
//   principal of the ledger canister
//   own aggregator id
// the constructor arguments are passed like this:
//   dfx deploy --argument='(principal "aaaaa-aa")' aggregator
// alternatively, the argument can be placed in dfx.json according to this scheme:
// https://github.com/dfinity/sdk/blob/ca578a30ea27877a7222176baea3a6aa368ca6e8/docs/dfx-json-schema.json#L222-L229
actor class AggregatorAPI(ledger : Principal, ownId : Aggregator.AggregatorId, lookupTableCapacity: Nat) {
  let aggregator_ = Aggregator.Aggregator(ledger, ownId, lookupTableCapacity);

  type Result<X,Y> = R.Result<X,Y>;

  /** Create a new transaction request.
  * Here we init it and put to the lookup table.
  * If the lookup table is full, we try to reuse the slot with oldest unapproved request
  */
  public shared({ caller }) func submit(tx: Tx.Tx): async Result<Aggregator.GlobalId, Aggregator.SubmitError> {
    aggregator_.submit(caller, tx);
  };

  /** Approve request. If the caller made the last required approvement, it:
  * - marks request as approved
  * - removes transaction request from the unapproved list
  * - enqueues the request to the batch queue
  */
  public shared({ caller }) func approve(txId: Aggregator.GlobalId): async Result<(), Aggregator.NotPendingError> {
    aggregator_.approve(caller, txId);
  };

  /** Reject request. It marks request as rejected, but don't remove the request from unapproved list,
  * so it's status can still be queried until overwritten by newer requests
  */
  public shared({ caller }) func reject(txId: Aggregator.GlobalId): async Result<(), Aggregator.NotPendingError> {
    aggregator_.reject(caller, txId);
  };

  /** Query transaction request info */
  public query func txDetails(gid: Aggregator.GlobalId): async Result<Aggregator.TxDetails, Aggregator.GidError> {
    aggregator_.txDetails(gid);
  };

  public func resume() : async () = async aggregator_.resume();

  public query func stats() : async Aggregator.Stats = async aggregator_.stats();
  public query func state() : async Aggregator.State = async aggregator_.state();

  // TODO remove after testing OR make it available only to canister controller
  public func setMaxBatchBytes(value: Nat) : async () { aggregator_.maxBatchBytes := value; };
  public func setMaxBatchRequests(value: Nat) : async () { aggregator_.maxBatchRequests := value; };

  /** heartbeat function */
  system func heartbeat() : async () {
    await aggregator_.heartbeat();
  };

};
