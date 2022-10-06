#!/home/andy/bin/ic-repl -r local

function createLedger(aggregators) {
  let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
  call ic.install_code(
    record {
      arg = encode (aggregators);
      wasm_module = file("../../.dfx/local/canisters/ledger_test/ledger_test.wasm");
      mode = variant { install };
      canister_id = id.canister_id;
    },
  );
  id;
};

identity aggregator_mock;

let id = createLedger(vec { aggregator_mock });
let canister = id.canister_id;

// register 40,000 principals, generated from sequent Nat-s (0 - 39,999)
call canister.registerPrincipals(0, 10000, 256, false, 500);
call canister.registerPrincipals(10000, 10000, 256, false, 500);
call canister.registerPrincipals(20000, 10000, 256, false, 500);
call canister.registerPrincipals(30000, 10000, 256, false, 500);

identity user1;
call canister.openNewAccounts(1, false);
identity user2;
call canister.openNewAccounts(2, false);
call canister.issueTokens(user2, 0, variant { ft = record { 0; 800 } });
call canister.issueTokens(user2, 1, variant { ft = record { 0; 800 } });

identity aggregator_mock;

// test cycles of empty batch
let n = call canister.profile(vec { });
output("./test/performance_tests/cycle_stats.txt", stringify("Empty batch: ", n, "\n"));

// test cycles of batch with single empty Tx
let n = call canister.profile(vec {
  record {
    map = vec { };
    committer = opt user1;
  }
});
call canister.counters();
assert _.failedTxs == (0 : nat);
output("./test/performance_tests/cycle_stats.txt", stringify("Batch with one empty Tx: ", n, "\n"));

// test cycles of batch with one simple Tx
let n = call canister.profile(vec {
  record {
    map = vec {
        record {
          owner = user1;
          inflow = vec { record { 0; variant { ft = record { 0; 500 } } } };
          outflow = vec { };
          memo = null;
          autoApprove = false;
        };
        record {
          owner = user2;
          inflow = vec { };
          outflow = vec { record { 0; variant { ft = record { 0; 500 } } } };
          memo = null;
          autoApprove = false;
        }
    };
    committer = opt user1;
  }
});
call canister.counters();
assert _.failedTxs == (0 : nat);
output("./test/performance_tests/cycle_stats.txt", stringify("One simple Tx: ", n, "\n"));

// load 2**14 txs
let batch = call canister.createTestBatch(user2, user2, 16384);
let n = call canister.profile(batch);
call canister.counters();
assert _.failedTxs == (0 : nat);
output("./test/performance_tests/cycle_stats.txt", stringify("16,384 txs: ", n, "\n"));

// one the biggest possible Tx
let heavy_tx = call canister.generateHeavyTx(0);
let n = call canister.profile(vec { heavy_tx });
call canister.counters();
assert _.failedTxs == (0 : nat);
output("./test/performance_tests/cycle_stats.txt", stringify("Heavy tx: ", n, "\n"));

// full batch with biggest possible Tx-s
let n = call canister.profile(vec {
  heavy_tx; heavy_tx; heavy_tx; heavy_tx; heavy_tx;
});
call canister.counters();
assert _.failedTxs == (0 : nat);
output("./test/performance_tests/cycle_stats.txt", stringify("5 heavy tx-s (max possible batch): ", n, "\n"));

// uncomment for debug: check the error if any
//call canister.batchesHistory(5, 7);

// cycles above has wrong values if something went wrong. So check counters here:
call canister.counters();
assert _.failedTxs == (0 : nat);
assert _.totalBatches == (6 : nat);
assert _.totalTxs == (16392 : nat);
assert _.succeededTxs == (16392 : nat);
