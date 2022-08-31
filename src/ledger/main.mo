import { nyi } "mo:base/Prelude";
import Prelude "mo:base/Prelude";
import List "mo:base/List";
import RBTree "mo:base/RBTree";
import { compare } "mo:base/Principal";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// ledger
// the constructor arguments are:
//   initial list of the canister ids of the aggregators
// more can be added later with add_aggregator()
// the constructor arguments are passed like this:
//   dfx deploy --argument='(vec { principal "aaaaa-aa"; ... })' ledger 
actor class Ledger(initial_aggregators : [Principal]) {

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type GlobalTxId = T.GlobalTxId;
  type AssetId = T.AssetId;
  type Asset = T.Asset;
  type Batch = T.Batch;

  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  type OwnerId = Nat;

  // data structures

  // list of all aggregators by their principals
  // TODO: insert hard-coded principals of all aggregators
  let aggregators = List.fromArray<Principal>([]);

  // The map from principal to short id is stored in a single `RBTree`:
  let owners : RBTree.RBTree<Principal, OwnerId> = RBTree.RBTree<Principal, OwnerId>(compare);

  // The content of all accounts is stored in an array of arrays
  var accounts : [var [var Asset]] = [var [var]];

  // The first index is the owner id and the second index is the subaccount id 
  // For example, a particular balance in a fungible token is accessed like this:
  // let #ft(id, balance) = accounts[owner_id][subaccount_id]

  // updates

  public func openNewAccounts(amount: Nat): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  public func processBatch(batch: Batch): async [{ #transactionId: GlobalTxId; #err: Nat }] {
    nyi();
  };

  // queries

  public query func nAggregators(): async Nat {
    nyi();
  };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> {
    nyi();
  };

  public query func nAccounts(): async Result<Nat, { #NotFound; }> {
    nyi();
  };

  public query func asset(sid: SubaccountId): async Result<Asset, { #NotFound; #SubaccountNotFound; }> {
    nyi();
  };

  // debug interface

  public query func all_assets(owner : Principal) : async Result<[Asset], { #NotFound; }> {
    nyi();
  };

  // admin interface

  // add one aggregator principal
  // authorization is admin-only
  public func add_aggregator(p : Principal) : async Result<(),()> {
    nyi();
  };
};
