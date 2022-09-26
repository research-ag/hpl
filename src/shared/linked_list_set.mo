import AssocList "mo:base/AssocList";
import List "mo:base/List";

module LinkedListSet {

  /**
  * A simple linked list based set
  */
  public class LinkedListSet<T>(eq : (T, T) -> Bool) {
    private var _set: AssocList.AssocList<T, ()> = List.nil<(T, ())>();

    /** add item to set. Returns true if element added, false if it already was there */
    public func put(item : T) : Bool {
      let (s2, oldValue) = AssocList.replace<T,()>(_set, item, eq, ?());
      _set := s2;
      switch (oldValue) {
        case (?ov) false;
        case (null) true;
      };
    };

  };
};
