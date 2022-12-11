module {
  public type Stats = { 
    txs : { submitted : Nat; queued: Nat; rejected: Nat; batched: Nat; processed: Nat; failed: Nat }; 
    batches : { sent: Nat; processed: Nat; failed: Nat }; 
    heartbeats : Nat 
  };

  public class Tracker() {
    let txs = {
      var submitted = 0;
      var queued = 0;
      var rejected = 0;
      var batched = 0;
      var processed = 0;
      var failed = 0; // failed to send, in a failed batch
    };
    let batches = {
      var sent = 0;
      var processed = 0;
      var failed = 0;
    };
    var heartbeats = 0;

    public func add(item : {#submit; #queue; #reject; #batch: Nat; #processed: Nat; #error: Nat; #heartbeat}) =
      switch item {
        // tx
        case (#submit) txs.submitted += 1;
        case (#queue) txs.queued += 1;
        case (#reject) txs.rejected += 1;
        // batch
        case (#batch n) { batches.sent += 1; txs.batched += n };
        case (#processed n) { batches.processed += 1; txs.processed += n };
        case (#error n) { batches.failed += 1; txs.failed += n };
        // heartbeat
        case (#heartbeat) heartbeats += 1 
      };

    public func stats() : Stats = {
      txs = { 
        submitted = txs.submitted;
        queued = txs.queued;
        rejected = txs.rejected;
        batched = txs.batched;
        processed = txs.processed;
        failed = txs.failed;
      };
      batches = {
        sent = batches.sent;
        processed = batches.processed;
        failed = batches.failed;
      };
      heartbeats = heartbeats
    }
  };
}
