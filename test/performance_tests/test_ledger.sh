#!/home/andy/bin/ic-repl -r local

function createLedger(aggregators) {
  let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
  call ic.install_code(
    record {
      arg = encode (aggregators);
      wasm_module = file("../../.dfx/local/canisters/ledger/ledger.wasm");
      mode = variant { install };
      canister_id = id.canister_id;
    },
  );
  id;
};

function createLedgerUtil(ledger) {
  let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
  call ic.install_code(
    record {
      arg = encode (ledger);
      wasm_module = file("../../.dfx/local/canisters/ledger_test_util/ledger_test_util.wasm");
      mode = variant { install };
      canister_id = id.canister_id;
    },
  );
  id;
};

identity aggregator_mock;

let id = createLedger(vec { aggregator_mock });
let canister = id.canister_id;
let utilId = createLedgerUtil(canister);
let utilCanister = utilId.canister_id;

// register 1,000,000 principals, generated from sequent Nat-s (0 - 999,999)
call utilCanister.registerPrincipals(0, 40000, 256, false, 500);
call utilCanister.registerPrincipals(40000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(80000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(120000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(160000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(200000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(240000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(280000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(320000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(360000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(400000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(440000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(480000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(520000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(560000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(600000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(640000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(680000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(720000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(760000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(800000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(840000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(880000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(920000, 40000, 256, false, 500);
call utilCanister.registerPrincipals(960000, 40000, 256, false, 500);

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
output("./test/performance_tests/cycle_stats.txt", stringify("One simple Tx: ", n, "\n"));

// load 2**14 txs
let batch = call utilCanister.createTestBatch(user2, user2, 16384);
let n = call canister.profile(batch);
output("./test/performance_tests/cycle_stats.txt", stringify("16,384 txs: ", n, "\n"));

call utilCanister.generateHeavyTx(0);

// one the biggest possible Tx
let tx = call utilCanister.generateHeavyTx(0);
let n = call canister.profile(vec { tx });
output("./test/performance_tests/cycle_stats.txt", stringify("Heavy tx: ", n, "\n"));

// uncomment for debug: check the error if any
call canister.batchesHistory(4, 6);

// cycles above has wrong values if something went wrong. So check counters here:
call canister.counters();
assert _.failedTxs == (0 : nat);
assert _.totalBatches == (5 : nat);
assert _.totalTxs == (16387 : nat);
assert _.succeededTxs == (16387 : nat);
