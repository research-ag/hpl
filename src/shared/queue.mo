import Deque "mo:base/Deque";

module HPLQueue {

  /** A FIFO queue, which preserves amount of pushed and popped values */
  public class HPLQueue<T>() {
    private var deque: Deque.Deque<T> = Deque.empty<T>();
    private var pushCtr : Nat = 0;
    private var popCtr : Nat = 0;

    /** number of items that were ever pushed to the queue */
    public func pushesAmount(): Nat = pushCtr;

    /** number items that were ever popped from the queue */
    public func popsAmount(): Nat = popCtr;

    /** the current length of the queue */
    public func size(): Nat = pushCtr - popCtr;

    /** insert value into the queue */
    public func enqueue(item: T) {
      deque := Deque.pushFront(deque, item);
      pushCtr += 1;
    };

    /** get next value from the queue */
    public func peek(): ?T {
      Deque.peekBack(deque);
    };

    /** get next value from the queue and remove it */
    public func dequeue(): ?T {
      let popResult = Deque.popBack(deque);
      switch (popResult) {
        case (?(updatedDec, item)) {
          popCtr += 1;
          deque := updatedDec;
          return ?item;
        };
        case (null) null;
      };
    };
  };
};
