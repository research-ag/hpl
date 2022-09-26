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

  public type TxValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #SubaccountsNotUnique; #OwnersNotUnique; #WrongAssetType; #AutoApproveNotAllowed };

  /** transaction request validation function. Optionally returns list of balances delta if success */
  public func validateTx(tx: T.Tx, checkPrincipalUniqueness: Bool): R.Result<(), TxValidationError> {
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };
    // checking balances equilibrium
    let assetBalanceMap = TrieMap.TrieMap<T.AssetId, Int>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) });
    // checking owners uniqueness
    let ownersSet = LinkedListSet.LinkedListSet<Principal>(Principal.equal);
    // main loop
    for (contribution in tx.map.vals()) {
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
      // checking subaccounts uniqueness
      let subaccountsSet = LinkedListSet.LinkedListSet<Nat>(Nat.equal);
      for ((subaccountId, asset) in contribution.inflow.vals()) {
        if (not subaccountsSet.put(subaccountId)) {
          return #err(#SubaccountsNotUnique);
        };
        switch asset {
          case (#ft (id, quantity)) {
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
        if (not subaccountsSet.put(subaccountId)) {
          return #err(#SubaccountsNotUnique);
        };
        switch asset {
          case (#ft (id, quantity)) {
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
    #ok();
  }
}
