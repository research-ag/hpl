import T "types";
import Array "mo:base/Array";
import HPLQueue "queue";

module SlotTable {

  type Tx = T.Tx;
  type LocalId = T.LocalId;
  type Slot<X> = {
    // value `none` means the slot is empty
    var value : ?X;
    // must be initialized to 0
    var counter : Nat;
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
  public class SlotTable<X>() {
    // number of slots available in the table
    let capacity = 16777216;
    // chain of all unused slots
    let unused : HPLQueue.HPLQueue<Nat> = HPLQueue.HPLQueue<Nat>();
    // slots array
    let slots : [Slot<X>] = Array.tabulate<Slot<X>>(16777216, func(n : Nat) {
      // during initialization, fill the queue with 0...<capacity> indexes
      unused.enqueue(n);
      { var value = null; var counter = 0; };
    });

    /** adds an element to the table.
    * If the table is not full then take an usued slot, write value and return unique local id;
    * if the table is full then return null
    */
    public func add(element : X) : ?LocalId {
      var slotIndex = unused.dequeue();
      switch (slotIndex) {
        case (?si) ?insertValue(element, si, false);
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
          unused.enqueue(slotIndex);
          slot.value := null;
        };
      };
    };

    /** returns slot and it's index for provided local id. Returns null if slot was overwritten */
    private func getSlotInfoByLid(lid : LocalId) : ?(Slot<X>, Nat) {
      let slotIndex = lid % 2**24;
      let counterValue = lid / 2**24;
      let slot = slots[slotIndex];
      if (slot.counter != counterValue) {
        return null;  // slot was overwritten
      };
      return ?(slot, slotIndex);
    };

    /** inserts value to slot with provided index, updates counter if needed; fgenerates and returns local id  */
    private func insertValue(element: X, slotIndex: Nat, incrementIfZero : Bool) : LocalId {
      let slot = slots[slotIndex];
      if (slot.counter > 0 or incrementIfZero) {
        slot.counter := slot.counter + 1;
      };
      let lid : LocalId = slot.counter*2**24 + slotIndex;
      slot.value := ?element;
      return lid;
    };
  };
};
