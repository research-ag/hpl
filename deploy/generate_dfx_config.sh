#!/bin/sh
cd "$(dirname "$0")"

agg_amount=0
wallets=[]
dfx_json='{
  "canisters": {'
create_canisters_sh='cd "$(dirname "$0")"
cd ..'

i=0
for line in $(cat wallet_principals.txt); do
  wallets[i]=$line
  if [ "$i" -eq "0" ]
  then
    dfx_json=$dfx_json'
    "ledger": {
      "main": "src/ledger/ledger_api.mo",
      "candid": "src/ledger/ledger.did",
      "type": "motoko"
    }'
    create_canisters_sh=$create_canisters_sh'
dfx canister --network ic create --wallet '$line' --with-cycles 100000000000 ledger'
  else
    dfx_json=$dfx_json',
    "agg'$((i-1))'": {
      "main": "src/aggregator/aggregator_api.mo",
      "candid": "src/aggregator/aggregator.did",
      "type": "motoko"
    }'
    create_canisters_sh=$create_canisters_sh'
dfx canister --network ic create --wallet '$line' --with-cycles 100000000000 agg'$((i-1))
    agg_amount=$((++agg_amount))
  fi
  i=$((++i))
done

dfx_json=$dfx_json'
  },
  "defaults": {
    "build": {
      "args": "",
      "packtool": ""
    }
  },
  "dfx": "0.12.0-beta.2",
  "networks": {
    "local": {
      "bind": "127.0.0.1:8000",
      "type": "ephemeral"
    }
  },
  "version": 1
}'

deploy_canisters_sh='cd "$(dirname "$0")"
cd ..'
deploy_canisters_sh=$deploy_canisters_sh'
dfx deploy --network ic --wallet '"${wallets[0]}"' ledger --argument='"'"'(vec { '
for i in $(seq $agg_amount); do
    deploy_canisters_sh=$deploy_canisters_sh'principal "'"'"'$(dfx canister id agg'$((i-1))')'"'"'"; '
done
deploy_canisters_sh=$deploy_canisters_sh'})'"'"
for i in $(seq $agg_amount); do
    deploy_canisters_sh=$deploy_canisters_sh'
dfx deploy --network ic --wallet '"${wallets[i]}"' agg'$((i-1))' --argument='"'"'(principal "'"'"'$(dfx canister id ledger)'"'"'", '$((i-1))', 65536)'"'"
done

echo "$dfx_json" > ../dfx.json
echo "$create_canisters_sh" > create_canisters.sh
echo "$deploy_canisters_sh" > deploy_canisters.sh

