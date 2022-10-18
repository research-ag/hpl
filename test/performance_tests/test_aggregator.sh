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

identity user;

let tx = call canister.generateSimpleTx(user, 0, user, 1, 10);
call canister.submit(tx);
// should be automatically put into batch, since approved
let batch = call canister.getNextBatch();
assert batch[0] != null;

