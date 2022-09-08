import T "types";
import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";

module {

  type TxValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted };

  public func validateTx(tx: T.Tx): R.Result<(), TxValidationError> {
    if (tx.map.size() > T.max_contribution) {
      return #err(#MaxContributionsExceeded);
    };
    for (contribution in tx.map.vals()) {
      if (contribution.inflow.size() + contribution.outflow.size() > T.max_flows) {
        return #err(#MaxFlowsExceeded);
      };
      switch (contribution.memo) {
        case (?m) {
          if (m.size() > T.max_memo_size) {
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
      let assetBalanceMap: TrieMap.TrieMap<T.AssetId, Int> = TrieMap.TrieMap<T.AssetId, Int>(func (a : T.AssetId, b: T.AssetId) : Bool { a == b }, func (a : Nat) { Nat32.fromNat(a) });
      for ((subaccountId, asset) in contribution.inflow.vals()) {
        switch asset {
          case (#ft (id, quantity)) {
            let currentBalance : ?Int = assetBalanceMap.get(id);
            switch (currentBalance) {
              case (?b) assetBalanceMap.put(id, b + quantity);
              case (null) assetBalanceMap.put(id, quantity);
            };
          };
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
        };
      };
      for (balance in assetBalanceMap.vals()) {
        if (balance != 0) {
          return #err(#FlowsNotBroughtToZero);
        };
      };
    };
    return #ok;
  }
}
