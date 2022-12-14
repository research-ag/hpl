#!/usr/local/bin/ic-repl

function createLedger(aggregators) {
  let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
  call ic.install_code(
    record {
      arg = encode (aggregators);
      wasm_module = file("../.dfx/local/canisters/ledger_test/ledger_test.wasm");
      mode = variant { install };
      canister_id = id.canister_id;
    },
  );
  id;
};

identity aggregator_mock;

let id = createLedger(vec { aggregator_mock });
let canister = id.canister_id;

// register one fungible token (asset id)
identity ftController;
call canister.createFungibleToken();

// register 40,000 principals, generated from sequent Nat-s (0 - 39,999)
call canister.registerPrincipals(0, 10000, 256, 500);
call canister.registerPrincipals(10000, 10000, 256, 500);
call canister.registerPrincipals(20000, 10000, 256, 500);
call canister.registerPrincipals(30000, 10000, 256, 500);

identity user1;
call canister.openNewAccounts(1, 0);
identity user2;
call canister.openNewAccounts(2, 0);
call canister.issueTokens(user2, 0, variant { ft = record { 0; 800 } });
call canister.issueTokens(user2, 1, variant { ft = record { 0; 800 } });

identity aggregator_mock;

// test cycles of empty batch
let n = call canister.profile(vec { });
output("cycle_stats.txt", stringify("[LED] Empty batch: ", n, "\n"));

// test cycles of batch with single empty Tx
let n = call canister.profile(vec {
  record {
    map = vec { }
  }
});
call canister.stats();
assert _.all.txsFailed == (0 : nat);
output("cycle_stats.txt", stringify("[LED] Batch with one empty Tx: ", n, "\n"));

// test cycles of batch with one simple Tx
let n = call canister.profile(vec {
  record {
    map = vec {
        record {
          owner = user1;
          inflow = vec { record { variant { sub = 0 }; variant { ft = record { 0; 500 } } } };
          outflow = vec { };
          mints = vec { };
          burns = vec { };
          memo = null;
        };
        record {
          owner = user2;
          inflow = vec { };
          outflow = vec { record { variant { sub = 0 }; variant { ft = record { 0; 500 } } } };
          mints = vec { };
          burns = vec { };
          memo = null;
        }
    }
  }
});
call canister.stats();
assert _.all.txsFailed == (0 : nat);
output("cycle_stats.txt", stringify("[LED] One simple Tx: ", n, "\n"));

// load 2**14 txs
let batch = call canister.createTestBatch(user2, 16384);
let n = call canister.profile(batch);
call canister.stats();
assert _.all.txsFailed == (0 : nat);
output("cycle_stats.txt", stringify("[LED] 16,384 txs: ", n, "\n"));

// one the biggest possible Tx
let heavy_tx = call canister.generateHeavyTx(0, record { appendMemo = true; failLastFlow = false });
let n = call canister.profile(vec { heavy_tx });
call canister.stats();
assert _.all.txsFailed == (0 : nat);
output("cycle_stats.txt", stringify("[LED] Heavy tx: ", n, "\n"));

// full batch with biggest possible Tx-s
let heavy_tx = call canister.generateHeavyTx(0, record { appendMemo = false; failLastFlow = false });
let n = call canister.profile(vec {
  heavy_tx; heavy_tx; heavy_tx; heavy_tx; heavy_tx;
});
call canister.stats();
assert _.all.txsFailed == (0 : nat);
output("cycle_stats.txt", stringify("[LED] 5 heavy tx-s: ", n, "\n"));

// Tx which fails in the very end
let heavy_tx = call canister.generateHeavyTx(0, record { appendMemo = true; failLastFlow = true });
let n = call canister.profile(vec { heavy_tx });
call canister.stats();
assert _.all.txsFailed == (1 : nat);
output("cycle_stats.txt", stringify("[LED] Heavy tx with failed last outflow: ", n, "\n"));

// uncomment for debug: check the error if any
//call canister.batchesHistory(5, 7);

// cycles above has wrong values if something went wrong. So check counters here:
call canister.stats();
assert _.all.txsFailed == (1 : nat);
assert _.all.batches == (7 : nat);
assert _.all.txs == (16393 : nat);
assert _.all.txsSucceeded == (16392 : nat);
