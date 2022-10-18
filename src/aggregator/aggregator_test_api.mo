import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Aggregator "./aggregator";
import LedgerAPI "../ledger/ledger_api";
import R "mo:base/Result";
import T "../shared/types";
import C "../shared/constants";
import Blob "mo:base/Blob";

// aggregator
// the constructor arguments are:
//   principal of the ledger canister
//   own aggregator id
// the constructor arguments are passed like this:
//   dfx deploy --argument='(principal "aaaaa-aa")' aggregator
// alternatively, the argument can be placed in dfx.json according to this scheme:
// https://github.com/dfinity/sdk/blob/ca578a30ea27877a7222176baea3a6aa368ca6e8/docs/dfx-json-schema.json#L222-L229
actor class AggregatorTestAPI(ledger_ : Principal, ownId : Aggregator.AggregatorId, lookupTableCapacity: Nat) {
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

  public func getNextBatch() : async Aggregator.Batch {
    Array.map(aggregator_.getNextBatchRequests(), func (req: Aggregator.TxRequest): Aggregator.Tx = req.tx);
  };

  public query func generateSimpleTx(sender: Principal, senderSubaccountId: T.SubaccountId, receiver: Principal, receiverSubaccountId: T.SubaccountId, amount: Nat): async Aggregator.Tx {
    if (sender == receiver) {
      {
        map = [{
          owner = sender;
          inflow = [ (receiverSubaccountId, #ft(0, amount)) ];
          outflow = [ (senderSubaccountId, #ft(0, amount)) ];
          memo = null;
          autoApprove = false;
        }];
        committer = null;
      };
    } else {
      {
        map = [{
          owner = sender;
          inflow = [];
          outflow = [ (senderSubaccountId, #ft(0, amount)) ];
          memo = null;
          autoApprove = false;
        }, {
          owner = receiver;
          inflow = [ (receiverSubaccountId, #ft(0, amount)) ];
          outflow = [];
          memo = null;
          autoApprove = false;
        }];
        committer = null;
      };
    };
  };

};
