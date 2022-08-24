import HPLTypes "../shared/types";

actor {

  type QueueNumber = Nat;
  type Acceptance = [Bool];

  type TransferInfo = {
    transfer : HPLTypes.TransferId;
    requester : Principal;
    status : { #pending : Acceptance; #accepted : QueueNumber; #rejected : Bool  };
  };

  public func request(transfer: HPLTypes.Transfer): async { #ok: HPLTypes.TransferId ; #err: Nat } {
    // TODO
    #err 1;
  };

  public func accept(transferId: HPLTypes.TransferId): async { #ok: HPLTypes.TransferId ; #err: Nat } {
    // TODO
    #err 1;
  };

  public func reject(transferId: HPLTypes.TransferId): async { #ok: HPLTypes.TransferId ; #err: Nat } {
    // TODO
    #err 1;
  };

  public query func transferDetails(transferId: HPLTypes.TransferId): async { #ok: TransferInfo ; #err: Nat } {
    // TODO
    #err 1;
  };

};
