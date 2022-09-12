/**
* A simple implementation of doubly linked list pattern
* It is a very optimistic: we can expose references to cell, assuming that no other
* part of code will modify prev/next links and break list integrity
* it does not have additional checks for preserving list integrity for the sake of performance
* please do not modify cells manually, use only functions of this class for operating the list
*/
import Iter "mo:base/Iter";
import Array "mo:base/Array";

module DoublyLinkedList {
  public class Cell<T>(list: DoublyLinkedList<T>, val: T) = _self {
    private func self() : Cell<T> {
      _self;
    };

    public var value = val;
    public var prev: ?Cell<T> = null;
    public var next: ?Cell<T> = null;
    let dll: DoublyLinkedList<T> = list;

    public func removeFromList() {
      dll.removeCell(self());
    };
  };

  public class DoublyLinkedList<T>() = _self {
    private func self() : DoublyLinkedList<T> {
      _self;
    };

    private var head: ?Cell<T> = null;
    private var tail: ?Cell<T> = null;
    private var length: Nat = 0;

    /** get amount of elements */
    public func size(): Nat {
      return length;
    };

    /** append element to the ending of the list */
    public func pushBack(val: T): Cell<T> {
      var cell: Cell<T> = Cell<T>(self(), val);
      switch (tail) {
        case (?t) {
          t.next := ?cell;
          cell.prev := ?t;
          tail := ?cell;
          length := length + 1;
        };
        case (null) {
          tail := ?cell;
          head := ?cell;
          length := 1;
        };
      };
      cell;
    };

    /** remove and return last value */
    public func popBack(): ?T {
      switch (tail) {
        case (null) return null;
        case (?c) {
          c.removeFromList();
          return ?c.value;
        };
      };
    };

    /** append element to the beginning of the list */
    public func pushFront(val: T): Cell<T> {
      var cell: Cell<T> = Cell<T>(self(), val);
      switch (head) {
        case (?h) {
          h.prev := ?cell;
          cell.next := ?h;
          head := ?cell;
          length := length + 1;
        };
        case (null) {
          tail := ?cell;
          head := ?cell;
          length := 1;
        };
      };
      cell;
    };

    /** remove and return first value */
    public func popFront(): ?T {
      switch (head) {
        case (null) return null;
        case (?c) {
          c.removeFromList();
          return ?c.value;
        };
      };
    };

    /** remove value by index. Returns this value */
    public func removeByIndex(index: Nat): ?T {
      if (index == 0) {
        return popFront();
      };
      if (length > 0 and index + 1 == length) {
        return popBack();
      };
      var cell = head;
      switch (cell) {
        case (null) return null;
        case (?c) {
          let iter = toIterCells();
          var curCell : ?Cell<T> = null;
          for (i in Iter.range(0, index)) {
            curCell := iter.next();
          };
          switch (curCell) {
            case (null) null;
            case (?cc) {
              cc.removeFromList();
              return ?cc.value;
            };
          };
        };
      };
    };

    /** removes cell. Has much better performance than deleting by index.
    * Dangerous if receive cell not from this list
    */
    public func removeCell(cell: Cell<T>) {
      switch (cell.prev) {
        case (?p) p.next := cell.next;
        case (null) head := cell.next;
      };
      switch (cell.next) {
        case (?n) n.prev := cell.prev;
        case (null) tail := cell.prev;
      };
      length := length - 1;
    };

    public func toIterCells() : Iter.Iter<Cell<T>> {
      var cell = head;
      object {
        public func next() : ?Cell<T> =
          switch cell {
            case (?c) {
              cell := c.next;
              return ?c;
            };
            case _ null;
          };
      };
    };

    public func toIter() : Iter.Iter<T> {
      var cells = toIterCells();
      object {
        public func next() : ?T =
          switch (cells.next()) {
            case (?c) ?c.value;
            case _ null;
          };
      };
    };
  };
};
