import Iter "mo:base/Iter";

module {
  public func arrayFindIndex<A>(xs: [A], f : A -> Bool): { #Found: Nat; #NotFound } {
    for (i in Iter.range(0, xs.size())) {
      if (f(xs[i])) {
        return #Found(i);
      }
    };
    return #NotFound();
  }
}
