// A simple Motoko smart contract.
import { isNull } "mo:base/Option";

type Node = {
  var previous: ?Node; // points towards head
  var next: ?Node; // points towards tail
  value : Nat;
  };

let pool = object OrderedPool {
  public var head : ?Node = null;
  public var tail : ?Node = null;
  // push = append to tail
  public func push(val : Nat) {
    let new_node = { 
      var previous : ?Node = tail; 
      var next : ?Node = null; 
      value = val 
    };
    switch (tail) {
      case (null) { head := ?new_node };
      case (?t) { t.next := ?new_node };
    };
    tail := ?new_node;
  };
  // pop = remove from head
  public func pop() : ?Nat {
    switch (head) {
      case (null) { null };
      case (?h) {
        let val = h.value;
        if (isNull(h.next)) { tail := null };
        head := h.next;
        ?val
      };
    }
  };
  // remove node
  public func remove(node : Node) {
    switch (node.previous) {
      case (?y) { y.next := node.next };
      case (null) { head := node.next };
    };
    switch (node.next) {
      case (?y) { y.previous := node.previous };
      case (null) { tail := node.previous };
    }
  };
  // for testing and debugging purposes:
  // get n-th node from head
  public func get_front(n : Nat) : ?Node {
    front_rec(head, n)
  };
  public func front_rec(h : ?Node, n : Nat) : ?Node {
    switch(h) {
      case (null) { null };
      case (?hr) {
        switch (n) {
          case (0) { h };
          case (m) { front_rec(hr.next, m-1) };
        };
      };
    };
  };
  // get n-th node from tail
  public func get_back(n : Nat) : ?Node {
    back_rec(tail, n)
  };
  public func back_rec(t : ?Node, n : Nat) : ?Node {
    switch(t) {
      case (null) { null };
      case (?tr) {
        switch (n) {
          case (0) { t };
          case (m) { back_rec(tr.previous, m-1) };
        };
      };
    };
  };
};

pool.push(1);
pool.push(2);
pool.push(3);

// pool.remove(pool.head);
ignore switch(pool.head) {
  case (null) { 0 };
  case (?h) { h.value };
};
//[pool.pop(), pool.pop(), pool.pop()]
switch (pool.get_front(2)) {
  case (null) { };
  case (?x) { pool.remove(x) }
};
pool.push(4);
pool.push(5);
switch (pool.get_back(1)) {
  case (null) { };
  case (?x) { pool.remove(x) }
};
[pool.pop(), pool.pop(), pool.pop(), pool.pop()]
