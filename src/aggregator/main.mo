import { nyi } "mo:base/Prelude";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// aggregator
actor {
  // type import work-around
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
  public func accept(transferId: TransferId): async Result<(),NotPendingError> {
    nyi();
  };

  public func reject(transferId: TransferId): async Result<(),NotPendingError> {
    nyi();
  };

  type TransferError = { #NotFound; };
  public query func transferDetails(transferId: TransferId): async Result<TransferInfo, TransferError> {
    nyi();
  };

};
