import { nyi } "mo:base/Prelude";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// aggregator
actor {
  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type Transaction = T.Transaction;
  type TransactionId = T.TransactionId;

  type QueueNumber = Nat;
  type Approvals = [Bool];
  type TransactionInfo = {
    id : TransactionId;
    submitter : Principal;
    status : { #pending : Approvals; #approved : QueueNumber; #rejected };
  };

  type SubmitError = { #NoSpace; #Invalid; };
  public func submit(transfer: Transaction): async Result<TransactionId, SubmitError> {
    nyi();
  };

  type NotPendingError = { #NotFound; #NoPart; #AlreadyRejected; #AlreadyApproved };
  public func approve(transferId: TransactionId): async Result<(),NotPendingError> {
    nyi();
  };

  public func reject(transferId: TransactionId): async Result<(),NotPendingError> {
    nyi();
  };

  type TransactionError = { #NotFound; };
  public query func txDetails(transferId: TransactionId): async Result<TransactionInfo, TransactionError> {
    nyi();
  };

};
