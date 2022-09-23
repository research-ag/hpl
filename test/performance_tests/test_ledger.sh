#!/home/andy/bin/ic-repl -r local
identity user;
identity aggregator_mock;
let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
  record {
    arg = encode (vec { aggregator_mock });
    wasm_module = file("../.dfx/local/canisters/ledger/ledger.wasm");
    mode = variant { install };
    canister_id = id.canister_id;
  },
);
let canister = id.canister_id;
call canister.processBatch(vec {
  record {
    map = vec { };
    committer = opt user;
  }
});
call canister.counters();
assert _.failedTxs == (0 : nat);
assert _.totalBatches == (1 : nat);
assert _.totalTxs == (1 : nat);
assert _.succeededTxs == (1 : nat);
