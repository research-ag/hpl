#!/home/andy/bin/ic-repl -r local

function createLedger(aggregators) {
  let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
  call ic.install_code(
    record {
      arg = encode (aggregators);
      wasm_module = wasm_profiling("../../.dfx/local/canisters/ledger/ledger.wasm");
      mode = variant { install };
      canister_id = id.canister_id;
    },
  );
  id;
};

identity user;
identity aggregator_mock;
let id = createLedger(vec { aggregator_mock });
let canister = id.canister_id;

// test cycles of empty batch
call canister.processBatch(vec { });
output("./test/performance_tests/cycle_stats.txt", stringify("Empty batch: ", __cost__, "\n"));

// test cycles of batch with single empty Tx
call canister.processBatch(vec {
  record {
    map = vec { };
    committer = opt user;
  }
});
output("./test/performance_tests/cycle_stats.txt", stringify("Batch with one empty Tx: ", __cost__, "\n"));

// test cycles of batch with one simple Tx
identity user2;
call canister.openNewAccounts(1, false);
identity user1;
call canister.openNewAccounts(1, false);
// give user2 800 tokens
call canister.issueTokens(user2, 0, variant { ft = record { 0; 800 } });

identity aggregator_mock;
call canister.processBatch(vec {
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
    committer = opt user;
  }
});
output("./test/performance_tests/cycle_stats.txt", stringify("One simple Tx: ", __cost__, "\n"));

// cycles above has wrong values if something went wrong. So check counters here:
call canister.counters();
assert _.failedTxs == (0 : nat);
assert _.totalBatches == (3 : nat);
assert _.totalTxs == (2 : nat);
assert _.succeededTxs == (2 : nat);

