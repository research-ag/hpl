.PHONY: all build
all: create build install

create:
	dfx canister create --all

build: 
	dfx build --check

install-ledger:
	dfx canister install --argument='(vec { principal "$(shell dfx canister id aggregator)" })' ledger

install-agg:
	dfx canister install --argument='(principal "$(shell dfx canister id ledger)", 0, 65536)' aggregator

install: install-ledger install-agg

reinstall-ledger:
	echo yes | dfx canister install --mode reinstall --argument='(vec { principal "$(shell dfx canister id aggregator)" })' ledger

reinstall-agg:
	echo yes | dfx canister install --mode reinstall --argument='(principal "$(shell dfx canister id ledger)", 0, 65536)' aggregator

re-install: reinstall-ledger reinstall-agg