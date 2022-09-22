.PHONY: all build
all: create build

create:
	dfx canister create --all

build: 
	dfx build --check

install:
	dfx canister install --argument='(principal "'$(shell dfx canister id ledger)'", 0)' agg0
	dfx canister install --argument='(principal "'$(shell dfx canister id ledger)'", 1)' agg1
	dfx canister install --mode reinstall --argument='(vec { principal "'$(shell dfx canister id agg0)'; principal "'$(shell dfx canister id agg1)'" })' ledger

reinstall:
	echo yes | dfx canister install --mode reinstall --argument='(principal "'$(shell dfx canister id ledger)'", 0)' agg0
	echo yes | dfx canister install --mode reinstall --argument='(principal "'$(shell dfx canister id ledger)'", 1)' agg1
	echo yes | dfx canister install --mode reinstall --argument='(vec { principal "'$(shell dfx canister id agg0)'; principal "'$(shell dfx canister id agg1)'" })' ledger
