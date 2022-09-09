import T "types";
import Array "mo:base/Array";
import { nyi; xxx } "mo:base/Prelude";
import Iter "mo:base/Iter";
import DLL "dll";

module SlotTable {

  type Tx = T.Tx;
  type LocalId = T.LocalId;

  /*
  We implement our lookup data structure as a lookup table (array) with a fixed number of slots.
  The slots are numbered 0,..,N-1.

  If 256 new transactions are submitted per second and never approved then, in a table with N=2**24 slots, they stay for ~18h before their slot gets overwritten.

  Each slot is an element of the following type:
    value : stored the tx request if the slot is currently used
    counter : counts how many times the slot has already been used (a trick to generate a unique local id)
    next/prev_index : used to track the order in which slots are to be used
  */

  type Slot<X> = {
      var value : ?X; // value `none` means the slot is empty
      var counter : Nat; // must be initialized to 0
      var chainAppearance : ?(DLL.DoublyLinkedList<Nat>, DLL.Cell<Nat>); // a direct reference to the chain containing this slot index and cell in it for fast access
  };

  /*
  Our lookup table is the following object.
  The `unused` chain contains all unused slot indices and defines the order in which they are filled with new tx requests.
  The `unapproved` chain contains all used slot indices that contain a unapproved tx request and defines the order in which they are to be overwritten.

  We currently utilize only one unapproved chain. In the future there can be multiple chains. A principal can buy its own chain of a certain capacity for a fee.
  Then the principal's own requests cannot be overwritten by others. But there is an recurring fee to reserve the chain capacity.
  */

  public class SlotTable<X>() {

    let capacity = 16777216; // number of slots available in the table

    // chain of all unused slots
    let unused : DLL.DoublyLinkedList<Nat> = DLL.DoublyLinkedList<Nat>();
    let unapproved : DLL.DoublyLinkedList<Nat> = DLL.DoublyLinkedList<Nat>(); // chain of all used slots with a unapproved tx request

    // see below for explanation of the Slot type
    let slots : [Slot<X>] = Array.tabulate<Slot<X>>(16777216, func(n : Nat) {
      { var value = null; var counter = 0; var chainCell = null; var chainAppearance = null };
    });
    // fill unused chain and set cell references
    for (i in Iter.range(0, 16777215)) {
        slots[i].chainAppearance := ?(unused, unused.push(i));
    };

    // add an element to the table
    // if the table is not full then take an usued slot (the slot will shift to unapproved)
    // if the table is full but there are unapproved slots then overwrite the oldest unapproved slot
    // if the table is full and there are no unapproved slots then abort
    public func add(element : X) : ?LocalId {
      var slotIndex = unused.shift();
      switch (slotIndex) {
        case (?si) {
          insertValue(element, si, false);
        };
        case (null) {
          slotIndex := unapproved.shift();
          switch (slotIndex) {
            case (?si) {
              insertValue(element, si, true);
            };
            case (null) null;
          };
        };
      };
    };

    // look up an element by id and return it
    // abort if the id cannot be found
    public func get(lid : LocalId) : ?X {
      let slotInfo = getSlotInfoByLid(lid);
      switch (slotInfo) {
        case (null) null;
        case (?(slot, index)) slot.value;
      };
    };

    // look up an element by id and mark its slot
    // abort if the id cannot be found
    public func mark(lid : LocalId) : ?X {
      let slotInfo = getSlotInfoByLid(lid);
      switch (slotInfo) {
        case (null) null;
        case (?(slot, slotIndex)) {
          switch (slot.chainAppearance) {
            case (null) null;
            case (?(chain, cell)) {
              // TODO check that it is really in unapproved chain
              // if (chain != unapproved) {
              //   return null;
              // };
              chain.removeCell(cell);
              slot.chainAppearance := null;
              slot.value;
            };
          };
        };
      };
    };

    // look up an element by id and empty its slot
    // ignore if the id cannot be found
    public func remove(lid : LocalId) : () {
      let slotInfo = getSlotInfoByLid(lid);
      switch (slotInfo) {
        case (null) {};
        case (?(slot, slotIndex)) {
          switch (slot.chainAppearance) {
            case (null) {};
            case (?(chain, cell)) {
              chain.removeCell(cell);
              slot.chainAppearance := null;
            };
          };
          slot.chainAppearance := ?(unused, unused.push(slotIndex));
          slot.value := null;
        };
      };
    };

    private func insertValue(element: X, slotIndex: Nat, incrementIfZero : Bool) : ?LocalId {
      let slot = slots[slotIndex];
      if (slot.counter > 0 or incrementIfZero) {
        slot.counter := slot.counter + 1;
      };
      let lid : LocalId = slot.counter*2**24 + slotIndex;
      slot.value := ?element;
      slot.chainAppearance := ?(unapproved, unapproved.push(slotIndex));
      return ?lid;
    };

    private func getSlotInfoByLid(lid : LocalId) : ?(Slot<X>, Nat) {
      let slotIndex = lid % 2**24;
      let counterValue = lid / 2**24;
      let slot = slots[slotIndex];
      if (slot.counter != counterValue) {
        return null;  // slot was overwritten
      };
      return ?(slot, slotIndex);
    };

  };
};

/*
Further details about the implementation of the functions:

If a new element is added and the unused chain is non-empty then:
  - the first slot is popped from the `unused` chain
  - for this slot:
    - the new element is stored in the `value` field of the slot
    - the local id to be returned is composed of the index of the slot and the `counter` field of the slot, e.g.:
        lid := counter*2**24 + slot_index
    - the `counter` field of the slot is incremented
    - the slot is pushed to the `unapproved` chain

If a new element is added, the unused chain is empty and the unapproved chain is non-empty then:
  - the first slot is popped from the `unapproved` chain and used as above to
    - store the element
    - build local id
    - increment `counter` value

When a lookup happens then the local id is first decomposed to obtain the slot id, e.g.
  slot_index := lid % 2**24;
  counter_value := lid / 2**24;
If the `counter` value in slot `slot_index` does not equal `counter_value` then it means the local id entry is no longer stored (has been overwritten) and the lookup failed.
If it equals and the `value` field in the slot is `none` then it means the local id entry is no longer stored (removed) and the lookup failed.
Otherwise the lookup was successful.

If a used slot gets marked (happens when the tx request gets approved) then it is removed from the `unapproved` chain.

If the element in a used slot is removed then:
  - the value in the slot is set to `none`
  - the slot is pushed to the `unused` chain.

So the theoretical transitions of a slot are:
  unused ->(add) unapproved ->(remove) unused
  unused ->(add) unapproved ->(mark) not in any chain ->(remove) unused

In practice what happens is:
  unused_chain ->(tx is added) unapproved ->(tx gets fully approved) not in any chain ->(tx gets batched) unused
*/
