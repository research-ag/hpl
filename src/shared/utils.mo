import TrieMap "mo:base/TrieMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";

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
  /** concat iterable of iterables to one single iterable */
  public func flattenIter<T>(source: Iter.Iter<Iter.Iter<T>>): Iter.Iter<T> {
    var currentIter: ?Iter.Iter<T> = source.next();
    let peekNext = func (): {#ok: T; #CurrentIterEmpty; #LastIterEmpty } = switch (currentIter) {
      case (?iter) {
        switch (iter.next()) {
          case (null) #CurrentIterEmpty;
          case (?val) #ok(val);
        };
      };
      case (null) #LastIterEmpty;
    };
    object {
      public func next() : ?T = switch (peekNext()) {
        case (#ok val) ?val;
        case (#CurrentIterEmpty) {
          currentIter := source.next();
          next();
        };
        case (#LastIterEmpty) null;
      };
    };
  };

  // append a single element to an immutable array
  public func append<T>(arr: [T], val: T): [T] {
    let s = arr.size();
    Array.tabulate<T>(s + 1, func(i) { if (i < s) arr[i] else val })
  };

  // append n elements to a mutable array, all initialized with the same value
  public func appendVar<T>(arr: [var T], n: Nat, val: T): [var T] {
    let s = arr.size();
    Array.tabulateVar<T>(s + n, func(i) { if (i < s) arr[i] else val })
  };

};
