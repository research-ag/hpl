import TrieMap "mo:base/TrieMap";

module {
  public func arrayFindIndex<A>(xs: [A], f : A -> Bool): { #Found: Nat; #NotFound } {
    for (i in xs.keys()) {
      if (f(xs[i])) {
        return #Found(i);
      }
    };
    return #NotFound();
  };

  public func trieMapGetOrCreate<K, V>(map: TrieMap.TrieMap<K, V>, key: K, createFunc : () -> V): V {
    let existing = map.get(key);
    switch (existing) {
      case (?entry) entry;
      case (null) {
        let entry: V = createFunc();
        map.put(key, entry);
        entry;
      };
    };
  };
};
