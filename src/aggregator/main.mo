import { nyi } "mo:base/Prelude";

// import types (pattern matching not available)
import T "../shared/types";
import R "mo:base/Result";

// aggregator
actor {
  // imported types (pattern matching not available)
  type Result<X,Y> = R.Result<X,Y>;
  type Transfer = T.Transfer;
  type TransferId = T.TransferId;

  type QueueNumber = Nat;
  type Acceptance = [Bool];
  type TransferInfo = {
    transfer : TransferId;
    requester : Principal;
    status : { #pending : Acceptance; #accepted : QueueNumber; #rejected };
  };

  type RequestError = { #NoSpace; #Invalid; };
  public func request(transfer: Transfer): async Result<TransferId, RequestError> {
    nyi();
  };

  type NotPendingError = { #NotFound; #NoPart; #AlreadyRejected; #AlreadyAccepted };
  public func accept(transferId: TransferId): async { #ok; #err : NotPendingError } {
    nyi();
  };

  public func reject(transferId: TransferId): async { #ok; #err : NotPendingError } {
    nyi();
  };

  type TransferError = { #NotFound; };
  public query func transferDetails(transferId: TransferId): async Result<TransferInfo, TransferError> {
    nyi();
  };

};
