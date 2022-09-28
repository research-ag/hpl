import AssocList "mo:base/AssocList";
import List "mo:base/List";

module LinkedListSet {

  /**
  * A simple linked list set
  */
  public class LinkedListSet<T>(eq : (T, T) -> Bool) {
    private var _list: AssocList.AssocList<T, ()> = List.nil<(T, ())>();

    /** add item to set. Returns true if element added, false if it already was there */
    public func put(item : T) : Bool {
      let (l, oldValue) = AssocList.replace<T,()>(_list, item, eq, ?());
      _list := l;
      switch (oldValue) {
        case (?ov) false;
        case (null) true;
      };
    };

  };
};
