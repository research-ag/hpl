import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";

import T "types";
import C "constants";
import u "utils";

module {

  public type TxValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted; #OwnersNotSorted; #WrongAssetType; #AutoApproveNotAllowed };

  /** transaction request validation function. Optionally returns list of balances delta if success */
  public func validateTx(tx: T.Tx): R.Result<(), TxValidationError> {
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };
    var lastOwnerPrincipal : { #empty; #val: Principal } = #empty;
    for (contribution in tx.map.vals()) {
      switch (lastOwnerPrincipal) {
        case (#val oid) {
          if (contribution.owner <= oid) {
            return #err(#OwnersNotSorted);
          };
        };
        case (#empty) {};
      };
      lastOwnerPrincipal := #val(contribution.owner);
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
      // checking balances equilibrium
      let assetBalanceMap = TrieMap.TrieMap<T.AssetId, Int>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) });
      for ((subaccountId, asset) in contribution.inflow.vals()) {
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
        switch asset {
          case (#ft (id, quantity)) {
            let currentBalance : ?Int = assetBalanceMap.get(id);
            switch (currentBalance) {
              case (?b) {
                let newBalance = b - quantity;
                if (newBalance < 0) {
                  return #err(#FlowsNotBroughtToZero);
                };
                assetBalanceMap.put(id, newBalance);
              };
              case (null) {
                // out flows are being processed after in flows, so if we have non-zero out flow and did not have in flow,
                // it will never add up to zero
                if (quantity > 0) {
                  return #err(#FlowsNotBroughtToZero);
                };
              };
            };
          };
          case (#none _) assert false; // should never happen
        };
      };
      for (balance in assetBalanceMap.vals()) {
        if (balance != 0) {
          return #err(#FlowsNotBroughtToZero);
        };
      };
    };
    #ok();
  }
}
