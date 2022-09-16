module {
  public func arrayFindIndex<A>(xs: [A], f : A -> Bool): { #Found: Nat; #NotFound } {
    for (i in xs.keys()) {
      if (f(xs[i])) {
        return #Found(i);
      }
    };
    return #NotFound();
  };
  /** check that items in two sorted arays with unique values are unique between each other
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 6, 7, 8], Nat.compare); => true
  Example: isSortedArraysUnique<Nat>([0, 2, 4], [1, 3, 4, 7, 8], Nat.compare); => false
  */
  public func isSortedArraysUnique<T>(a: [T], b: [T], cmp: (a: T, b: T) -> { #less; #equal; #greater }): Bool {
    var aPtr = 0;
    var bPtr = 0;
    if (a.size() == 0 or b.size() == 0) {
      return true;
    };
    while (aPtr < a.size() and bPtr < b.size()) {
      switch (cmp(a[aPtr], b[bPtr])) {
        case (#equal) return false;
        case (#less) aPtr += 1;
        case (#greater) bPtr += 1;
      };
    };
    return true;
  };
};
