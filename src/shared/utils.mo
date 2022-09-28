import TrieMap "mo:base/TrieMap";
import Iter "mo:base/Iter";

module {
  public func arrayFindIndex<A>(xs: [A], f : A -> Bool): { #Found: Nat; #NotFound } {
    for (i in xs.keys()) {
      if (f(xs[i])) {
        return #Found(i);
      }
    };
    return #NotFound();
  };
  /** check that items in two sorted arrays with unique values are unique between each other
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 6, 7, 8], Nat.compare); => true
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 4, 7, 8], Nat.compare); => false
  */
  public func isSortedArraysUnique<T>(a: [T], b: [T], cmp: (a: T, b: T) -> { #less; #equal; #greater }): Bool {
    var aPtr = 0;
    var bPtr = 0;
    while (aPtr < a.size() and bPtr < b.size()) {
      switch (cmp(a[aPtr], b[bPtr])) {
        case (#equal) return false;
        case (#less) aPtr += 1;
        case (#greater) bPtr += 1;
      };
    };
    return true;
  };
  /** concat two iterables into one */
  public func iterConcat<T>(a: Iter.Iter<T>, b: Iter.Iter<T>): Iter.Iter<T> {
    var aEnded: Bool = false;
    object {
      public func next() : ?T {
        if (aEnded) {
          return b.next();
        };
        let nextA = a.next();
        switch (nextA) {
          case (?val) ?val;
          case (null) {
            aEnded := true;
            b.next();
          };
        };
      };
    };
  };
};
