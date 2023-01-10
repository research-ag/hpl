#!/usr/local/bin/ic-repl

// import system wallet. Use this canister as a caller and remote principal of virtual accounts
import wallet = "${WALLET_ID:-rwlgt-iiaaa-aaaaa-aaaaa-cai}" as "wallet.did";
identity wallet_controller "~/.config/dfx/identity/default/identity.pem";

// create ledger
let lid = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
  record {
    arg = encode ( vec { } );
    wasm_module = file("../.dfx/local/canisters/ledger/ledger.wasm");
    mode = variant { install };
    canister_id = lid.canister_id;
  },
);
let ledger = lid.canister_id;

// create minter
let mid = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
call ic.install_code(
  record {
    arg = encode ( opt ledger );
    wasm_module = file("../.dfx/local/canisters/minter/minter.wasm");
    mode = variant { install };
    canister_id = mid.canister_id;
  },
);
let minter = mid.canister_id;
call minter.init();
let assetId = call minter.assetId();

// register user and accounts
identity user;
let sid = call ledger.openNewAccounts(1, assetId);
let vid = call ledger.openVirtualAccount(record { asset = variant { ft = record { 0; 1000000 } }; remotePrincipal = wallet; backingSubaccountId = sid.ok });

// mint tokens
identity wallet_controller;
let res = call wallet.wallet_call(
  record {
    args = encode (user, vid.ok);
    cycles = 50000;
    method_name = "mint";
    canister = minter;
  }
);
res;
