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

identity anotherUser;
identity user;

let tx = call canister.generateSimpleTx(user, 0, anotherUser, 0, 10);
let res0 = call canister.profileSubmit(tx);
res0;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] submit simple Tx: ", res0[0], "\n"));

let tx = call canister.generateSimpleTx(user, 0, user, 1, 10);
let res1 = call canister.profileSubmit(tx);
res1;
// should be automatically put into batch, since approved
let batch = call canister.getNextBatch();
assert batch[0] != null;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] submit + auto-enqueue simple Tx: ", res1[0], "\n"));

let heavy_tx = call canister.generateHeavyTx(0);
let res2 = call canister.profileSubmit(heavy_tx);
res2;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] submit heavy tx: ", res2[0], "\n"));

// clear batch if any
call canister.getNextBatch();

identity anotherUser;
let res3 = call canister.profileApprove(res0[1].ok);
res3;
// should be automatically put into batch, since approved
let batch = call canister.getNextBatch();
assert batch[0] != null;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] approve + equeue simple Tx: ", res3[0], "\n"));

identity user;
let tx = call canister.generateSimpleTx(user, 0, anotherUser, 0, 10);
call canister.submit(tx);
let gid = _.ok;
identity anotherUser;
let res5 = call canister.profileReject(gid);
res5;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] reject simple Tx: ", res5[0], "\n"));

// big batch
identity user;
call canister.submitManySimpleTxs(1000, user, 0, user, 1, 10);
let res6 = call canister.profileGetNextBatch();
res6;
output("./test/performance_tests/cycle_stats.txt", stringify("[AGG] prepare big batch: ", res6[0], "\n"));
