/**
* A simple implementation of doubly linked list pattern, designed for fast removing item in the middle of it
* It is a very optimistic: we can expose references to cell, assuming that no other
* part of code will modify prev/next links and break list integrity
* it does not have additional checks for preserving list integrity for the sake of performance
* please do not modify cells manually, use only functions of this class for operating the list
*/
import Iter "mo:base/Iter";
import Array "mo:base/Array";

module DoublyLinkedList {
  public class Cell<T>(list: DoublyLinkedList<T>, val: T) = self {

    public var value = val;
    public var prev: ?Cell<T> = null;
    public var next: ?Cell<T> = null;
    public var dll: ?DoublyLinkedList<T> = ?list;

    public func removeFromList() {
      switch (dll) {
        case (?l) l.removeCell(self);
        case (null) ();
      };
    };
  };

  public class DoublyLinkedList<T>() = self {

    private var head: ?Cell<T> = null;
    private var tail: ?Cell<T> = null;
    private var length: Nat = 0;

    /** get amount of elements */
    public func size(): Nat = length;

    /** append element to the ending of the list */
    public func pushBack(val: T): Cell<T> {
      let cell: Cell<T> = Cell<T>(self, val);
      switch (tail) {
        case (?t) t.next := ?cell;
        case (null) head := ?cell;
      };
      cell.prev := tail;
      tail := ?cell;
      length += 1;
      cell;
    };

    /** remove and return last value */
    public func popBack(): ?T = popCell(tail);

    /** append element to the beginning of the list */
    public func pushFront(val: T): Cell<T> {
      let cell: Cell<T> = Cell<T>(self, val);
      switch (head) {
        case (?h) h.prev := ?cell;
        case (null) tail := ?cell;
      };
      cell.next := head;
      head := ?cell;
      length += 1;
      cell;
    };

    /** remove and return first value */
    public func popFront(): ?T = popCell(head);

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
      length -= 1;
      // cleanup cell data: should dissociate cell from the list
      cell.prev := null;
      cell.next := null;
      cell.dll := null;
    };

    /** get cells iterator */
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

    /** get values iterator */
    public func toIter() : Iter.Iter<T> {
      let cells = toIterCells();
      object {
        public func next() : ?T =
          switch (cells.next()) {
            case (?c) ?c.value;
            case _ null;
          };
      };
    };

    private func popCell(cell : ?Cell<T>) : ?T {
      switch (cell) {
        case (?c) {
          removeCell(c);
          ?c.value
        };
        case (null) null
      };
    };
  };
};
