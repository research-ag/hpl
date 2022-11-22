This script will flood aggregator canisters with some simple request as quickly as possible 
by launching 8 nodejs workers, each creates own user pair, token, mints this token to userA (anonymous) and 
starts flooding simple Tx-s, where userA transmits 1 token to userB in each Tx. 
Estimated combined speed is 1000TPS (1k transactions per second) with good network conditions

How to launch it:
1) Make sure canisters are built (`<project_root>/.dfx/local/canisters` exists)
2) Make sure canisters deployed and there are correct canister ids in `<project_root>/deploy/canister_ids.json`
3) `cd <project_root>/test/hpl_agent`
4) `npm ci`
5) `sh entrypoint.sh`

Observe logs in `<project_root>/test/hpl_agent/logs` directory, one file per worker
