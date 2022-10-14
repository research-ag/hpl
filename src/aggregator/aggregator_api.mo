import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Aggregator "./aggregator";
import LedgerAPI "../ledger/ledger_api";
import Bool "mo:base/Bool";
import R "mo:base/Result";
import Iter "mo:base/Iter";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import C "../shared/constants";
import v "../shared/validators";
import u "../shared/utils";
import SlotTable "../shared/slot_table";
import HPLQueue "../shared/queue";
import DLL "../shared/dll";

// aggregator
// the constructor arguments are:
//   principal of the ledger canister
//   own aggregator id
// the constructor arguments are passed like this:
//   dfx deploy --argument='(principal "aaaaa-aa")' aggregator
// alternatively, the argument can be placed in dfx.json according to this scheme:
// https://github.com/dfinity/sdk/blob/ca578a30ea27877a7222176baea3a6aa368ca6e8/docs/dfx-json-schema.json#L222-L229
actor class AggregatorAPI(ledger_ : Principal, ownId : T.AggregatorId, lookupTableCapacity: Nat) {
  let aggregator_ = Aggregator.Aggregator(ledger_, ownId, lookupTableCapacity);

  type Result<X,Y> = R.Result<X,Y>;

  /* store the init arguments:
       - canister id of the ledger canister
       - own unique identifier of this aggregator
  */
  let ledger : Principal = ledger_;
  let selfAggregatorIndex: Aggregator.AggregatorId = ownId;

  // define the ledger actor
  let Ledger_actor = actor (Principal.toText(ledger)) : LedgerAPI.LedgerAPI;

  /** Create a new transaction request.
  * Here we init it and put to the lookup table.
  * If the lookup table is full, we try to reuse the slot with oldest unapproved request
  */
  public shared({ caller }) func submit(tx: Aggregator.Tx): async Result<Aggregator.GlobalId, Aggregator.SubmitError> {
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
  public query func txDetails(gid: Aggregator.GlobalId): async Result<Aggregator.TxDetails, Aggregator.TxError> {
    aggregator_.txDetails(gid);
  };

  /** heartbeat function */
  system func heartbeat() : async () {
    await aggregator_.heartbeat();
  };

};
