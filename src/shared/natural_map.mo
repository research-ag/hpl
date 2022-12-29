import Array "mo:base/Array";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import AssocList "mo:base/AssocList";
import List "mo:base/List";

module NaturalMap {

  /** An associative list, optimized for natural keys. Does not preserve elements order */
  public class NaturalMap<T>(bucketsAmount: Nat) {

    private var buckets: [var AssocList.AssocList<Nat, T>] = Array.init(bucketsAmount, null);

    public func find(key: Nat): ?T = AssocList.find(buckets[key % bucketsAmount], key, Nat.equal);

    public func replace(key: Nat, value: ?T): ?T {
      let bucketIndex = key % bucketsAmount;
      let (list, oldValue) = AssocList.replace<Nat, T>(buckets[bucketIndex], key, Nat.equal, value);
      buckets[bucketIndex] := list;
      oldValue;
    };

    public func clear() {
      buckets := Array.init(bucketsAmount, null);
    };

    public func toIter() : Iter.Iter<(Nat, T)> {
      var bi: Nat = 0;
      var iter = List.toIter(buckets[bi]);
      object {
        public func next() : ?(Nat, T) {
          while (bi < bucketsAmount) {
            switch (iter.next()) {
              case (?val) return ?val;
              case (null) {
                bi += 1;
                if (bi < bucketsAmount) {
                  iter := List.toIter(buckets[bi]);
                };
              };
            };
          };
          return null;
        };
      };
    };

  };
};