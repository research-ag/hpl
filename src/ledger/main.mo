import { nyi } "mo:base/Prelude";
import RBTree "mo:base/RBTree";
import Array "mo:base/Array";
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
  type GlobalId = T.GlobalId;
  type AssetId = T.AssetId;
  type Asset = T.Asset;
  type Batch = T.Batch;

  // Owners are tracked via a "short id" which is a Nat
  // Short ids (= owner ids) are issued consecutively
  type OwnerId = Nat;

  // data structures

  // list of all aggregators by their principals
  var aggregators = initial_aggregators;

  // The map from principal to short id is stored in a single `RBTree`:
  let owners : RBTree.RBTree<Principal, OwnerId> = RBTree.RBTree<Principal, OwnerId>(compare);

  /* 
  The content of all accounts is stored in an array of arrays.
  The first index is the owner id and the second index is the subaccount id 
  For example, a particular balance in a fungible token is accessed like this:
    let #ft(id, balance) = accounts[owner_id][subaccount_id]

  The outer array is of fixed-length N (currently, N=2**24).
  This means there is space for N different owners and N cannot grow.
  In the future we will replace this with our own implementation of an array that can grow.
  The currently available implementations Array and Buffer perform bad in their worst-case when it comes to extending them.

  When an owner open new subaccounts then we use Array.append to grow the owners array of subaccounts.
  We accept the inefficiency of that implementation until there is a better alternative.
  Since this isn't happening in a loop and happens only once during the canister call it is fine.
  */

  let accounts : [var [var Asset]] = Array.init(16777216, [var] : [var Asset]);

  // updates

  /*
  Open n new subaccounts. When `auto_approve` is true then all subaccounts will be set to be "auto approving".
  This setting cannot be changed anymore afterwards with the current API.

  Note that the owner does not specify a token id. The new subaccounts hold the Asset value none. 
  The token id of a subaccount is determined by the first inflow. 
  After that, the token id cannot be changed anymore with the current API.
  For any subsequent transaction the inflow has to match the token id of the subaccount or else is rejected.

  If the owner wants to set a subaccount's token id before the first inflow then the owner can make a transaction that has no inflows and an outflow of the token id and amount 0.
  That will set the Asset value in the subaccount to the wanted token id.
  */

  public func openNewAccounts(n: Nat, auto_approve : Bool): async Result<SubaccountId, { #NoSpace; }> {
    nyi();
  };

  /* 
  Process a batch of transactions. Each transaction only executes if the following conditions are met:
  - all subaccounts that are marked `auto_approve` in the transactions are also auto_approve in the ledger
  - all outflow subaccounts have matching token id and sufficient balance
  - all inflow subaccounts have matching token id (or Asset value `none`)
  - on a per-token id basis the sum of all outflows matches all inflows
  */

  // TODO: define a variant instead of error codes
  public func processBatch(batch: Batch): async [{ #gid: GlobalId; #err: Nat }] {
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
