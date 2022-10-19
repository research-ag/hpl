import Array "mo:base/Array";
import HPLQueue "queue";

module SlotTable {

  public type LocalId = Nat;

  type Slot<X> = {
    // value `none` means the slot is empty
    value : ?X;
    counter : Nat;
  };

  /** We implement our lookup data structure as a lookup table (array) with a fixed number of slots.
  The slots are numbered 0,..,N-1.

  Each slot is an element of the following type:
    value : stored the tx request if the slot is currently used
    counter : counts how many times the slot has already been used (a trick to generate a unique local id)

  Our lookup table is the following object.
  The `unused` queue contains all unused slot indices and defines the order in which they are filled with new tx requests.
  When adding element, we use the first slot index from the `unused` queue. If it's empty we abort operation: slot table is full
  When removing element, we put freed slot index to the `unused` queue, so it will be reused later
  */
  // `capacity` is a number of slots available in the table
  public class SlotTable<X>(capacity: Nat) {
    // total amount of pushes to the table
    private var pushCtr : Nat = 0;
    // chain of all slots, that can be reused
    let reuseQueue : HPLQueue.HPLQueue<Nat> = HPLQueue.HPLQueue<Nat>();
    // slots array
    let slots : [var Slot<X>] = Array.init<Slot<X>>(capacity, { value = null; counter = 0; });

    /** number of items that were ever pushed to the table */
    public func pushesAmount(): Nat = pushCtr;

    /** adds an element to the table.
    * If the table is not full then take an usued slot, write value and return unique local id;
    * if the table is full then return null
    */
    public func add(element : X) : ?LocalId {
      let slotIndex = if (pushCtr < capacity) { ?pushCtr } else { reuseQueue.dequeue() };
      switch (slotIndex) {
        case (?si) ?insertValue(element, si);
        case (null) null;
      };
    };

    /** look up an element by id and return it
    * abort if the id cannot be found or was overwritten (counter != slot.counter)
    */
    public func get(lid : LocalId) : ?X {
      let slotInfo = getSlotInfoByLid(lid);
      switch (slotInfo) {
        case (null) null;
        case (?(slot, index)) slot.value;
      };
    };

    /** look up an element by id and empty its slot
    * ignore if the id cannot be found
    */
    public func remove(lid : LocalId) : () {
      let slotInfo = getSlotInfoByLid(lid);
      switch (slotInfo) {
        case (null) {};
        case (?(slot, slotIndex)) {
          reuseQueue.enqueue(slotIndex);
          slots[slotIndex] := { value = null; counter = slot.counter; };
        };
      };
    };

    /** returns slot and it's index for provided local id. Returns null if slot was overwritten */
    private func getSlotInfoByLid(lid : LocalId) : ?(Slot<X>, Nat) {
      let slotIndex = lid % capacity;
      let counterValue = lid / capacity + 1;
      let slot = slots[slotIndex];
      if (slot.counter != counterValue) {
        return null;  // slot was overwritten
      };
      return ?(slot, slotIndex);
    };

    /** inserts value to slot with provided index, updates counter; generates and returns local id  */
    private func insertValue(element: X, slotIndex: Nat) : LocalId {
      slots[slotIndex] := { value = ?element; counter = slots[slotIndex].counter + 1; };
      pushCtr += 1;
      (slots[slotIndex].counter - 1)*capacity + slotIndex;
    };
  };
};
