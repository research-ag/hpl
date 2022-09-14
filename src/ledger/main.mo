import { nyi } "mo:base/Prelude";
import RBTree "mo:base/RBTree";
import Array "mo:base/Array";
import { compare } "mo:base/Principal";
import R "mo:base/Result";

// type imports
// pattern matching is not available for types during import (work-around required)
import T "../shared/types";

// ledger
// the constructor arguments are:
//   initial list of the canister ids of the aggregators
// more can be added later with addAggregator()
// the constructor arguments are passed like this:
//   dfx deploy --argument='(vec { principal "aaaaa-aa"; ... })' ledger
actor class Ledger(initialAggregators : [Principal]) {

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
  var aggregators: [Principal] = initialAggregators;

  // The map from principal to short id is stored in a single `RBTree`:
  let owners : RBTree.RBTree<Principal, OwnerId> = RBTree.RBTree<Principal, OwnerId>(compare);
  // track size of owners RBTree;
  var ownersAmount : Nat = 0;

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

  public shared({caller}) func openNewAccounts(n: Nat, auto_approve : Bool): async Result<SubaccountId, { #NoSpace; }> {
    var ownerId: ?OwnerId = null;
    // get or register owner ID
    let accountsResult = getPrincipalAccounts(caller);
    switch (accountsResult) {
      case (#ok (oid, acc)) ownerId := ?oid;
      case (#err err) {
        let regResult = registerAccount(caller);
        switch (regResult) {
          case (#err err) {};
          case (#ok (oid, acc)) ownerId := ?oid;
        };
      };
    };
    // update accounts
    switch (ownerId) {
      case (null) #err(#NoSpace);
      case (?oid) {
        let oldSize = accounts[oid].size();
        if (oldSize + n > 16777216) {
          return #err(#NoSpace);
        };
        // array.append seems to not work with var type
        accounts[oid] := Array.tabulateVar<Asset>(oldSize + n, func (n: Nat) {
          if (n < oldSize) {
            return accounts[oid][n];
          };
          return #none;
        });
        #ok(oldSize);
      };
    };
  };

  /*
  Process a batch of transactions. Each transaction only executes if the following conditions are met:
  - all subaccounts that are marked `auto_approve` in the transactions are also auto_approve in the ledger
  - all outflow subaccounts have matching token id and sufficient balance
  - all inflow subaccounts have matching token id (or Asset value `none`)
  - on a per-token id basis the sum of all outflows matches all inflows
  There is no return value.
  If the call returns (i.e. no system-level failure) the aggregator knows that the batch has been processed.
  If the aggregator catches a system-level failure then it knows that the batch has not been processed.
  */

  public func processBatch(batch: Batch): async () {
    nyi();
  };

  // queries

  public query func nAggregators(): async Nat { aggregators.size(); };

  public query func aggregatorPrincipal(aid: AggregatorId): async Result<Principal, { #NotFound; }> {
    if (aggregators.size() >= aid) {
      return #err(#NotFound);
    };
    #ok(aggregators[aid]);
  };

  public shared query ({caller}) func nAccounts(): async Result<Nat, { #NotFound; }> {
    let accounts = getPrincipalAccounts(caller);
    switch (accounts) {
      case (#err err) #err(err);
      case (#ok (oid, acc)) #ok(acc.size());
    };
  };

  public shared query ({caller}) func asset(sid: SubaccountId): async Result<Asset, { #NotFound; #SubaccountNotFound; }> {
    let accounts = getPrincipalAccounts(caller);
    switch (accounts) {
      case (#err err) #err(err);
      case (#ok (oid, acc)) {
        if (sid >= acc.size()) {
          return #err(#SubaccountNotFound);
        };
        #ok(acc[sid]);
      };
    };
  };

  // admin interface

  // add one aggregator principal
  // TODO authorization is admin-only
  public func addAggregator(p : Principal) : async Result<AggregatorId,()> {
    // AG: Array.append is deprecated due to bad performance, however in this case it appears more optimal than converting to buffer
    aggregators := Array.append(aggregators, [p]);
    // let aggBuffer: Buffer.Buffer<Principal> = Buffer.fromArray(aggregators);
    // aggBuffer.add(p);
    // aggregators := aggBuffer.toArray();
    #ok(aggregators.size() - 1);
  };

  // debug interface
  // TODO authorization is admin-only
  public query func allAssets(owner : Principal) : async Result<[Asset], { #NotFound; }> {
    let account = getPrincipalAccounts(owner);
    switch (account) {
      case (#ok acc) #ok(Array.freeze(acc.1));
      case (#err err) #err(err);
    };
  };

  // private functionality

  private func getPrincipalAccounts(principal: Principal) : Result<(OwnerId, [var Asset]), { #NotFound }> {
    let ownerId = owners.get(principal);
    switch (ownerId) {
      case (null) #err(#NotFound);
      case (?oid) #ok(oid, accounts[oid]);
    };
  };

  private func registerAccount(principal: Principal) : Result<(OwnerId, [var Asset]), { #NoSpace }> {
    let ownerId = ownersAmount;
    if (ownerId >= 16777216) {
      return #err(#NoSpace);
    };
    owners.put(principal, ownerId);
    ownersAmount += 1;
    accounts[ownerId] := Array.init<Asset>(0, #none);
    #ok(ownerId, accounts[ownerId]);
  };
};
