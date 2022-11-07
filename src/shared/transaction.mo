import R "mo:base/Result";
import AssocList "mo:base/AssocList";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";

import C "constants";

module {
  public type SubaccountId = Nat;
  public type AssetId = Nat;
  public type Asset = { 
    #ft : (id : AssetId, quantity : Nat);
  };
  public type Contribution = {
    owner : Principal;
    inflow : [(SubaccountId, Asset)];
    outflow : [(SubaccountId, Asset)];
    mints : [Asset];
    burns : [Asset];
    memo : ?Blob
  };
  // inflow/outflow encodes a map subaccount -> asset list
  // subaccount id must be strictly increasing throughout the list to rule out duplicate keys

  // Tx = Transaction
  // map is seen as a map from a principal to its contribution
  // the owner principals in each contribution must be strictly increasing throughout the list to rule out duplicate keys
  public type Tx = {
    map : [Contribution];
    committer : ?Principal
  };

  public type Batch = [Tx];
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

  func nFlows(c : Contribution) : Nat =
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
    Array.map(tx.map, func(c : Contribution) : Principal {c.owner});

  func isUnique(list : [Principal]) : Bool {
    var i = 1;
    while (i < list.size()) {
      var j = 0;
      while (j < i) {
        if (list[i] == list[j]) {
          return false
        };
        j += 1; 
      };
      i += 1;
    }; 
    true
  };

  func isStrictlyIncreasing(l : [Nat]) : Bool {
    var i = 1;
    while (i < l.size()) {
      if (l[i] <= l[i-1]) {
        return false
      };
      i += 1;
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

  func validateContribution(c : Contribution) : Result<(), ValidationError> {
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
    // flow quantities
    func exceeds(a : Asset) : Bool =
      switch a {
        case (#ft(_,q)) { q > C.flowMaxFtQuantity }
      };
    for (a in c.mints.vals()) {
      if (exceeds(a)) { return #err(#MaxFtQuantityExceeded) } 
    };
    for (a in c.burns.vals()) {
      if (exceeds(a)) { return #err(#MaxFtQuantityExceeded) } 
    };
    for (f in c.inflow.vals()) {
      if (exceeds(f.1)) { return #err(#MaxFtQuantityExceeded) } 
    };
    for (f in c.outflow.vals()) {
      if (exceeds(f.1)) { return #err(#MaxFtQuantityExceeded) } 
    };
    // sorting of subaccount ids in inflow and outflow
    let ids1 = Array.map<(Nat, Asset),Nat>(c.inflow, func(x) {x.0});
    let ids2 = Array.map<(Nat, Asset),Nat>(c.outflow, func(x) {x.0});
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
    var balanceMap : AssocList.AssocList<AssetId, Int> = null;
    func add(a : Asset) {
      switch a {
        case (#ft (id, quantity)) {
          let newValue = Option.get(AssocList.find(balanceMap, id, Nat.equal),0) + quantity;
          balanceMap := AssocList.replace(balanceMap, id, Nat.equal, ?newValue).0;
        };
      };
    };
    func sub(a : Asset) {
      switch a {
        case (#ft (id, quantity)) {
          let newValue = Option.get(AssocList.find(balanceMap, id, Nat.equal),0) - quantity;
          balanceMap := AssocList.replace(balanceMap, id, Nat.equal, ?newValue).0;
        };
      };
    };
    // build map
    for (contribution in tx.map.vals()) {
      for (a in contribution.mints.vals()) { add(a); };
      for (a in contribution.burns.vals()) { sub(a); };
      for (f in contribution.outflow.vals()) { add(f.1); };
      for (f in contribution.inflow.vals()) { sub(f.1); };
    };
    // test if map has negative entries
    func cons(id : Nat, quantity : Int, res : Bool) : Bool = res or (quantity < 0);
    if (AssocList.fold(balanceMap, false, cons)) {
      return #err(#FlowsNotBroughtToZero);
    };
    // everything passed, tx is ok
    #ok
  }
}