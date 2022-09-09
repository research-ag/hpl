import Deque "mo:base/Deque";

module HPLQueue {

  /** A queue, which preserves amount of pushed and popped values */
  public class HPLQueue<T>() {
    private var deque: Deque.Deque<T> = Deque.empty<T>();
    /*
    global counters
    pushCtr = number of items that were ever pushed to the queue
    popCtr = number items that were ever popped from the queue
    the difference between the two equals the current length of the queue
    */
    var pushCtr : Nat = 0;
    var popCtr : Nat = 0;

    public func pushesAmount(): Nat {
      pushCtr;
    };

    public func popsAmount(): Nat {
      popCtr;
    };

    public func enqueue(item: T) {
      deque := Deque.pushFront(deque, item);
      pushCtr := pushCtr + 1;
    };

    public func dequeue(): ?T {
      let popResult = Deque.popBack(deque);
      switch (popResult) {
        case (?(updatedDec, item)) {
          popCtr := popCtr + 1;
          deque := updatedDec;
          return ?item;
        };
        case (null) null;
      };
    };

    public func size(): Nat {
      pushCtr - popCtr;
    }

  };

};
