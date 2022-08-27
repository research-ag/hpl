import { nyi } "mo:base/Prelude";
import Prelude "mo:base/Prelude";
import List "mo:base/List";
import { RBTree } "mo:base/RBTree";
import { compare } "mo:base/Principal";

// type imports
// pattern matching is not available for types (work-around required)
import T "../shared/types";
import R "mo:base/Result";

// types


// ledger
actor {
  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;
  type AggregatorId = T.AggregatorId;
  type SubaccountId = T.SubaccountId;
  type TransactionId = T.TransactionId;
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
  let owners = RBTree<Principal, OwnerId>(compare);

  // The content of all accounts is stored in an array of array
  let accounts : [[Asset]] = [[]];

  // The first index is the owner id and the second index is the subaccount id 
  // For example, a particular balance in a fungible token is accessed like this:
  // let #ft(id, balance) = accounts[owner_id][subaccount_id]

  // updates

  public func openNewAccounts(amount: Nat): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  public func processBatch(batch: Batch): async [{ #transactionId: TransactionId; #err: Nat }] {
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
