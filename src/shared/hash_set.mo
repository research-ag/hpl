import TrieSet "mo:base/TrieSet";

module HashSet {

  /**
  * A class wrapper around TrieSet to more convenient usage
  * Has addition to motoko's TrieSet: returns boolean is element was present in the set when we putting it
  */
  public class HashSet<T>(hashFunc : (T) -> TrieSet.Hash, eq : (T, T) -> Bool) {
    private var _set: TrieSet.Set<T> = TrieSet.empty<T>();

    /** add item to set. Returns true if element added, false if it already was there */
    public func put(item : T) : Bool {
      let hash = hashFunc(item);
      let isInSet = TrieSet.mem<T>(_set, item, hash, eq);
      _set := TrieSet.put<T>(_set, item, hash, eq);
      not isInSet;
    };

  };
};
