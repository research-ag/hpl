import T "types";
import R "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import Nat32 "mo:base/Nat32";

module {

  type TransactionValidationError = { #FlowsNotBroughtToZero; #MaxContributionsExceeded; #MaxFlowsExceeded; #MaxMemoSizeExceeded; #FlowsNotSorted };

  public func validateTransaction(transaction: T.Tx): R.Result<(), TransactionValidationError> {
    if (transaction.map.size() > T.max_contribution) {
      return #err(#MaxContributionsExceeded);
    };
    for (contribution in transaction.map.vals()) {
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
      let assetBalanceMap: TrieMap.TrieMap<T.AssetId, Int> = TrieMap.TrieMap<T.AssetId, Int>(func (a : T.AssetId, b: T.AssetId) : Bool { a == b }, func (a : Nat) { Nat32.fromNat(a) });
      for (flows in [contribution.inflow, contribution.outflow].vals()) {
        let negate : Bool = flows == contribution.outflow;
        var lastSubaccountId : Nat = 0;
        for ((subaccountId, asset) in flows.vals()) {
          if (lastSubaccountId > 0 and subaccountId <= lastSubaccountId) {
            return #err(#FlowsNotSorted);
          };
          lastSubaccountId := subaccountId;
          switch asset {
            case (#ft (id, quantity)) {
              let currentBalance : ?Int = assetBalanceMap.get(id);
              switch (currentBalance) {
                case (?b) {
                  if (negate) {
                    assetBalanceMap.put(id, b - quantity);
                  } else {
                    assetBalanceMap.put(id, b + quantity);
                  };
                };
                case (null) {
                  // out flows are being processed after in flows, so if we have non-zero out flow and did not have in flow,
                  // it will never add up to zero
                  if (negate and quantity > 0) {
                    return #err(#FlowsNotBroughtToZero);
                  };
                  assetBalanceMap.put(id, quantity);
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
