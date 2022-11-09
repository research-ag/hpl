i=0
dfx_json='{
  "canisters": {'
create_canisters_sh=''
for line in $(cat wallet_principals.txt); do
  if [ "$i" -eq "0" ]
  then
    dfx_json=$dfx_json'
    "ledger": {
      "main": "src/ledger/ledger_api.mo",
      "candid": "src/ledger/ledger.did",
      "type": "motoko"
    }'
    create_canisters_sh='dfx canister --network ic create --wallet '$line' --with-cycles 100000000000 ledger'
  else
    dfx_json=$dfx_json',
    "agg'$((i-1))'": {
      "main": "src/aggregator/aggregator_api.mo",
      "candid": "src/aggregator/aggregator.did",
      "type": "motoko"
    }'
    create_canisters_sh=$create_canisters_sh'
dfx canister --network ic create --wallet '$line' --with-cycles 100000000000 agg'$((i-1))
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
echo "$dfx_json" > dfx.json
echo "$create_canisters_sh" > create_canisters.sh

