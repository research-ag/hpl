import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";

import T "types";
import C "constants";
import u "utils";

module {

  public type TxValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted; #WrongAssetType; };

  /** transaction request validation function. Optionally returns list of balances delta if success */
  public func validateTx(tx: T.Tx, returnBalanceDeltas: Bool): R.Result<?TrieMap.TrieMap<Principal, TrieMap.TrieMap<T.SubaccountId, (T.AssetId, Int)>>, TxValidationError> {
    if (tx.map.size() > C.maxContribution) {
      return #err(#MaxContributionsExceeded);
    };
    let balanceDeltas = TrieMap.TrieMap<Principal, TrieMap.TrieMap<T.SubaccountId, (T.AssetId, Int)>>(Principal.equal, Principal.hash);
    for (contribution in tx.map.vals()) {
      let balanceDeltaOwner: TrieMap.TrieMap<T.SubaccountId, (T.AssetId, Int)> = u.trieMapGetOrCreate<Principal, TrieMap.TrieMap<T.SubaccountId, (T.AssetId, Int)>>(
        balanceDeltas,
        contribution.owner,
        func () = TrieMap.TrieMap<T.SubaccountId, (T.AssetId, Int)>(Nat.equal, func (a : Nat) { Nat32.fromNat(a) }),
      );
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
            if (returnBalanceDeltas) {
              let currentDelta = u.trieMapGetOrCreate<T.SubaccountId, (T.AssetId, Int)>(balanceDeltaOwner, subaccountId, func () = (id, 0));
              if (id != currentDelta.1) {
                return #err(#WrongAssetType);
              };
              balanceDeltaOwner.put(subaccountId, (id, currentDelta.1 + quantity));
            };
          };
          case (#none) return #err(#WrongAssetType);
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
            if (returnBalanceDeltas) {
              let currentDelta = u.trieMapGetOrCreate<T.SubaccountId, (T.AssetId, Int)>(balanceDeltaOwner, subaccountId, func () = (id, 0));
              if (id != currentDelta.1) {
                return #err(#WrongAssetType);
              };
              balanceDeltaOwner.put(subaccountId, (id, currentDelta.1 - quantity));
            };
          };
          case (#none) assert false; // should never happen
        };
      };
      for (balance in assetBalanceMap.vals()) {
        if (balance != 0) {
          return #err(#FlowsNotBroughtToZero);
        };
      };
    };
    if (returnBalanceDeltas) {
      return #ok(?balanceDeltas);
    };
    return #ok(null);
  }
}
