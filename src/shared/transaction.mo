import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Array "mo:base/Array";

import T "types";
import C "constants";
import u "utils";
import LinkedListSet "linked_list_set";

module {
  public type Tx = T.Tx;
  public type ValidationError = { 
    #FlowsNotBroughtToZero; 
    #MaxContributionsExceeded; 
    #MaxFlowsExceeded; 
    #MaxFtQuantityExceeded; 
    #MaxMemoSizeExceeded; 
    #FlowsNotSorted; 
    #OwnersNotUnique 
  };

  // type import work-around
  type Result<X,Y> = R.Result<X,Y>;

  func nFlows(c : T.Contribution) : Nat =
    c.mints.size() + c.burns.size() + c.inflow.size() + c.outflow.size();

  // Tx size in bytes
  public func size(tx : Tx) : Nat {
    let contributions = tx.map.size(); 
    var flows = 0;
    for (c in tx.map.vals()) {
      flows += nFlows(c);
    };
    contributions * 34 + flows * 29
  }; 

  func owners(tx : Tx) : [Principal] = 
    Array.map(tx.map, func(c : T.Contribution) : Principal {c.owner});

  func isUnique(list : [Principal]) : Bool {
    let set = LinkedListSet.LinkedListSet<Principal>(Principal.equal);
    for (x in list.vals()) {
      if (not set.put(x)) {
        return false
      }
    };
    true
  };

  func isStrictlyIncreasing(l : [Nat]) : Bool {
    var i = 1;
    while (i < l.size()) {
      if (l[i] <= l[i-1]) {
        return false
      }
    }; 
    true
  };

  /** check that items in two sorted arrays with unique values are unique between each other
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 6, 7, 8], Nat.compare); => true
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 4, 7, 8], Nat.compare); => false
  */
  func isUniqueInBoth(a: [Nat], b: [Nat]) : Bool {
    var i = 0;
    var j = 0;
    while (i < a.size() and j < b.size()) {
      switch (Nat.compare(a[i],b[j])) {
        case (#equal) return false;
        case (#less) i += 1;
        case (#greater) j += 1
      }
    };
    true
  };

  func validateContribution(c : T.Contribution) : Result<(), ValidationError> {
    // memo size
    switch (c.memo) {
      case (?m) {
        if (m.size() > C.maxMemoSize) {
          return #err(#MaxMemoSizeExceeded);
        };
      };
      case (_) {};
    };
    // number of flows
    if (nFlows(c) > C.maxFlows) {
      return #err(#MaxFlowsExceeded);
    };
    // sorting of subaccount ids in inflow and outflow
    let ids1 = Array.map<(Nat, T.Asset),Nat>(c.inflow, func(x) {x.0});
    let ids2 = Array.map<(Nat, T.Asset),Nat>(c.outflow, func(x) {x.0});
    if (not isStrictlyIncreasing(ids1) or not isStrictlyIncreasing(ids2)) {
      return #err(#FlowsNotSorted)
    };
    // uniqueness of subaccount ids across inflow and outflow
    // this algorithm works only because subaccount ids are strictly increasing in both arrays
    if (not isUniqueInBoth(ids1, ids2)) {
      return #err(#FlowsNotSorted);
    };
    #ok
  };

  // validate tx, error describes why it is not valid
  public func validate(tx: Tx, checkPrincipalUniqueness: Bool): Result<(), ValidationError> {
    // number of contributions
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };

    // uniqueness of owners
    if (checkPrincipalUniqueness and not isUnique(owners(tx))) {
      return #err(#OwnersNotUnique)
    };

    // validate each contribution in isolation
    for (c in tx.map.vals()) {
      switch (validateContribution(c)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };

    // equilibrium of flows
    let assetBalanceMap = TrieMap.TrieMap<T.AssetId, Int>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) });
    for (contribution in tx.map.vals()) {
      let txAssetsIn: Iter.Iter<T.Asset> = u.iterConcat<T.Asset>(
        Iter.map<(T.SubaccountId, T.Asset), T.Asset>(contribution.inflow.vals(), func (flow) = flow.1),
        contribution.burns.vals()
      );
      let txAssetsOut: Iter.Iter<T.Asset> = u.iterConcat<T.Asset>(
        Iter.map<(T.SubaccountId, T.Asset), T.Asset>(contribution.outflow.vals(), func (flow) = flow.1),
        contribution.mints.vals()
      );
      for (asset in txAssetsIn) {
        switch asset {
          case (#ft (id, quantity)) {
            if (quantity > C.flowMaxFtQuantity) {
              return #err(#MaxFtQuantityExceeded);
            };
            let currentBalance : ?Int = assetBalanceMap.get(id);
            switch (currentBalance) {
              case (?b) assetBalanceMap.put(id, b + quantity);
              case (null) assetBalanceMap.put(id, quantity);
            };
          };
        };
      };
      for (asset in txAssetsOut) {
        switch asset {
          case (#ft (id, quantity)) {
            if (quantity > C.flowMaxFtQuantity) {
              return #err(#MaxFtQuantityExceeded);
            };
            let currentBalance : ?Int = assetBalanceMap.get(id);
            switch (currentBalance) {
              case (?b) assetBalanceMap.put(id, b - quantity);
              case (null) assetBalanceMap.put(id, -quantity);
            };
          };
        };
      };
    };
    for (balance in assetBalanceMap.vals()) {
      if (balance != 0) {
        return #err(#FlowsNotBroughtToZero);
      };
    };
    #ok
  }
}
