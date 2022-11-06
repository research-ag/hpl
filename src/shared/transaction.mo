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

  // validate tx, error describes why it is not valid
  public func validate(tx: Tx, checkPrincipalUniqueness: Bool): Result<(), ValidationError> {
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };
    // checking owners uniqueness
    if (checkPrincipalUniqueness and not isUnique(owners(tx))) {
        return #err(#OwnersNotUnique)
    };

    // checking balances equilibrium
    let assetBalanceMap = TrieMap.TrieMap<T.AssetId, Int>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) });
    // main loop
    for (contribution in tx.map.vals()) {
      if (contribution.inflow.size() + contribution.outflow.size() + contribution.mints.size() + contribution.burns.size() > C.maxFlows) {
        return #err(#MaxFlowsExceeded);
      };
      switch (contribution.memo) {
        case (?m) {
          if (m.size() > C.maxMemoSize) {
            return #err(#MaxMemoSizeExceeded);
          };
        };
        case (null) {};
      };
      // checking flows sorting
      for (flows in [contribution.inflow, contribution.outflow].vals()) {
        var lastSubaccountId : { #empty; #val: Nat } = #empty;
        for ((subaccountId, asset) in flows.vals()) {
          switch (lastSubaccountId) {
            case (#val lsid) {
              if (subaccountId <= lsid) {
                return #err(#FlowsNotSorted);
              };
            };
            case (#empty) {};
          };
          lastSubaccountId := #val(subaccountId);
        };
      };
      // check that subaccounts are unique in inflow + outflow
      // this algorithm works only if subaccounts are unique and sorted in both arrays, which is true here
      if (not u.isSortedArraysUnique<(T.SubaccountId, T.Asset)>(
        contribution.inflow,
        contribution.outflow,
        func (flowA, flowB) : {#equal; #greater; #less} = Nat.compare(flowA.0, flowB.0),
      )) {
        return #err(#FlowsNotSorted);
      };
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
