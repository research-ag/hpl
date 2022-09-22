import Array "mo:base/Array";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";

module CircularBuffer {

  /** A circular buffer, which preserves amount of pushed values */
  public class CircularBuffer<T>(capacity: Nat) {

    private var array: [var ?T] = Array.init(capacity, null);
    private var cursor: Nat = 0;

    private var pushCtr : Nat = 0;

    /** number of items that were ever pushed to the buffer */
    public func pushesAmount(): Nat = pushCtr;

    /** insert value into the buffer */
    public func put(item: T) {
      array[cursor] := ?item;
      cursor := wrapIndex(cursor + 1);
      pushCtr += 1;
    };

    /** get chunk of written values, filters out already overwritten values.
    * Example: slice(0, 1) will return array with the very first item, added to buffer, if it wasn't overwritten
    * slice(0, 2) returns two first items, if they weren't overwritten
    * slice(1, 2) returns second item, if it wasn't overwritten
    * if buffer(5) was filled with 10 values, slice(4, 6) will return only 5th value, because 4th was overwritten
    * buff.slice(buff.pushesAmount() - 1, buff.pushesAmount()) returns [last_item]
    */
    public func slice(startIndex: Nat, endIndex: Nat): [T] {
      // clamp indexes to buffer capacity/amount of already added elements
      let minIndex: Nat = if (pushCtr > capacity) { pushCtr - capacity } else { 0 };
      let start = Nat.max(minIndex, Nat.min(pushCtr, startIndex));
      let end = Nat.max(minIndex, Nat.min(pushCtr, endIndex));
      // cursor in buffer's array
      var readCursor = wrapIndex(start);
      let cursorEnd: Nat = readCursor + end - start;
      Iter.toArray(object {
        public func next() : ?T {
          if (readCursor >= cursorEnd) {
            return null;
          };
          var res: ?T = null;
          if (readCursor < capacity) {
            res := array[readCursor];
          } else {
            res := array[readCursor - capacity];
          };
          readCursor += 1;
          res;
        };
      });
    };

    private func wrapIndex(index: Int): Nat {
      var wrapped: Int = index % capacity;
      if (wrapped < 0) {
        wrapped += capacity;
      };
      return Int.abs(wrapped);
    };
  };
};
