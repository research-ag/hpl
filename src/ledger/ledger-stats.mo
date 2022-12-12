import Array "mo:base/Array";
import u "../shared/utils";

module {
  public class Tracker(nAggregators: Nat) {
    public var perAgg : [Ctr] = Array.tabulate<Ctr>(nAggregators, func(i) { Ctr() });
    public var direct : Ctr = Ctr();
    public var all : Ctr = Ctr();
    public var accounts : Nat = 0;
    public var owners : Nat = 0;
    public var assets : Nat = 0;

    public func record(source: {#agg : Nat; #direct}, event : {#batch; #txfail; #txsuccess}) {
      switch source {
        case (#agg i) perAgg[i].record(event);
        case (#direct) direct.record(event)
      };
      all.record(event);
    };

    public func add(item : {#accounts : Nat; #owner; #asset; #aggregator}) =
      switch item {
        case (#accounts(n)) accounts += n;
        case (#owner) owners += 1;
        case (#asset) assets += 1;
        case (#aggregator) {
          perAgg := u.append(perAgg, Ctr());
        }
      };

    public func get() : Stats = {
      perAgg = Array.tabulate<CtrState>(perAgg.size(), func(i) { perAgg[i].state() });
      direct = direct.state();
      all = all.state();
      registry = { owners = owners; accounts = accounts; assets = assets; aggregators = perAgg.size() }
    }
  };

  // tx counter (used once per source)
  type CtrState = { batches: Nat; txs: Nat; txsFailed: Nat; txsSucceeded: Nat };

  class Ctr() {
    public var batches : Nat = 0;
    public var txs : Nat = 0;
    public var txsFailed : Nat = 0;
    public var txsSucceeded : Nat = 0;

    public func record(event : {#batch; #txfail; #txsuccess}) =
      switch (event) {
        case (#batch) { 
          batches += 1; 
        };
        case (#txfail) { 
          txsFailed += 1;
          txs += 1;
        };
        case (#txsuccess) {
          txsSucceeded += 1;
          txs += 1;
        }
      };

    public func state() : CtrState = {
      batches = batches;
      txs = txs;
      txsFailed = txsFailed;
      txsSucceeded = txsSucceeded;
    };
  };

  // global stats
  public type Stats = { 
    perAgg : [CtrState]; 
    direct : CtrState; 
    all : CtrState; 
    registry : { 
      owners : Nat; 
      accounts : Nat; 
      assets : Nat;
      aggregators : Nat
    }
  };
}
