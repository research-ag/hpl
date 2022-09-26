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
