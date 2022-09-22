.PHONY: all build
all: create build install

create:
	dfx canister create --all

build: 
	dfx build --check

install-ledger:
	dfx canister install --argument='(vec { principal "$(shell dfx canister id agg0)"; principal "$(shell dfx canister id agg1)" })' ledger

install-agg:
	dfx canister install --argument='(principal "$(shell dfx canister id ledger)", 0)' agg0
	dfx canister install --argument='(principal "$(shell dfx canister id ledger)", 1)' agg1

install: install-ledger install-agg

reinstall-ledger:
	echo yes | dfx canister install --mode reinstall --argument='(vec { principal "$(shell dfx canister id agg0)"; principal "$(shell dfx canister id agg1)" })' ledger

reinstall-agg:
	echo yes | dfx canister install --mode reinstall --argument='(principal "$(shell dfx canister id ledger)", 0)' agg0
	echo yes | dfx canister install --mode reinstall --argument='(principal "$(shell dfx canister id ledger)", 1)' agg1

re-install: reinstall-ledger reinstall-agg
