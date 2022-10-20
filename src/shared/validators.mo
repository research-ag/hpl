import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";

import T "types";
import C "constants";
import u "utils";
import LinkedListSet "linked_list_set";

module {

  public type TxValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxFtQuantityExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted; #OwnersNotUnique; #WrongAssetType; #AutoApproveNotAllowed };

  /** transaction request validation function. Returns Tx size in bytes if success */
  public func validateTx(tx: T.Tx, checkPrincipalUniqueness: Bool): R.Result<Nat, TxValidationError> {
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };
    // checking balances equilibrium
    let assetBalanceMap = TrieMap.TrieMap<T.AssetId, Int>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) });
    // checking owners uniqueness
    let ownersSet = LinkedListSet.LinkedListSet<Principal>(Principal.equal);
    var contributionsAmount = 0;
    var flowsAmount = 0;
    // main loop
    for (contribution in tx.map.vals()) {
      contributionsAmount += 1;
      if (checkPrincipalUniqueness and not ownersSet.put(contribution.owner)) {
        return #err(#OwnersNotUnique);
      };
      if (contribution.autoApprove and contribution.outflow.size() > 0) {
        return #err(#AutoApproveNotAllowed);
      };
      if (contribution.inflow.size() + contribution.outflow.size() > C.maxFlows) {
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
          flowsAmount += 1;
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
      for ((subaccountId, asset) in contribution.inflow.vals()) {
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
          case (#none _) return #err(#WrongAssetType);
        };
      };
      for ((subaccountId, asset) in contribution.outflow.vals()) {
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
          case (#none _) assert false; // should never happen
        };
      };
    };
    for (balance in assetBalanceMap.vals()) {
      if (balance != 0) {
        return #err(#FlowsNotBroughtToZero);
      };
    };
    #ok(contributionsAmount * 34 + flowsAmount * 29);
  }
}
