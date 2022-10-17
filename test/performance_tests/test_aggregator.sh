#!/home/andy/bin/ic-repl -r local

identity ledger_mock;

let id = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
  record {
    arg = encode ( ledger_mock, (1 : nat), (65536 : nat) );
    wasm_module = file("../../.dfx/local/canisters/aggregator_test/aggregator_test.wasm");
    mode = variant { install };
    canister_id = id.canister_id;
  },
);
let canister = id.canister_id;

call canister.getNextBatch();
