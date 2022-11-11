#!/bin/sh
cd "$(dirname "$0")"

# functions
# header for deploy scripts: cd to <project_root>/deploy directory
GetDeployScriptHeader () {
  echo 'cd "$(dirname "$0")"'
}
# header for dfx.json
GetDfxJsonHeader () {
  echo '{
  "canisters": {'
}
# footer for dfx.json
GetDfxJsonFooter () {
  echo '
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
}
# canister definition in dfx.json. Arguments are: name, canister name
GetDfxJsonCanisterDefinition () {
   echo '
    "'$1'": {
      "wasm": "../.dfx/local/canisters/'$2'/'$2'.wasm",
      "candid": "../.dfx/local/canisters/'$2'/'$2'.did",
      "type": "custom"
    }'
}
# return canister principal candid string. Arguments are: canister name
GetCandidPrincipalOfCanister() {
  echo 'principal "'"'"'$(dfx canister id '$1' --network ic)'"'"'"'
}
# canister creation command. Arguments are: wallet principal, canister name
GetCanisterCreateCommand () {
   echo '
dfx canister --network ic create --wallet '$1' --with-cycles 100000000000 '$2
}
# canister deployment command. Arguments are: canister name, candid arguments
GetCanisterDeployCommand () {
   echo '
dfx deploy --network ic --no-wallet '$1' --argument='"'("$2")'"
}

# script body
dfx_json="$(GetDfxJsonHeader)"
create_canisters_sh="$(GetDeployScriptHeader)"
deploy_canisters_sh="$(GetDeployScriptHeader)"

# wallet file line counter
i=0
# arguments for ledger canister deploy: will be filled with aggregator id-s in a loop below
ledger_args='vec { '
for line in $(cat wallet_principals.txt); do
  if [ "$i" -eq "0" ]
  then
    # add ledger to dfx.json
    dfx_json=$dfx_json"$(GetDfxJsonCanisterDefinition ledger ledger)"
    # add ledger create command to create_canisters script
    create_canisters_sh=$create_canisters_sh"$(GetCanisterCreateCommand $line ledger)"
  else
    # add aggregator to dfx.json
    dfx_json=$dfx_json,"$(GetDfxJsonCanisterDefinition agg$((i-1)) aggregator)"
    # add aggregator create command to create_canisters script
    create_canisters_sh=$create_canisters_sh"$(GetCanisterCreateCommand $line agg$((i-1)))"
    # add aggregator id reference to ledger arguments
    ledger_args=$ledger_args$(GetCandidPrincipalOfCanister agg$((i-1)))'; '
    # build aggregator arguments
    agg_args="$(GetCandidPrincipalOfCanister ledger), $((i-1)), 65536"
    # add aggregator deploy command to deploy_canisters script
    deploy_canisters_sh=$deploy_canisters_sh"$(GetCanisterDeployCommand agg$((i-1)) "$agg_args")"
  fi
  i=$((++i))
done
ledger_args=$ledger_args' }'
# add ledger deploy command to deploy_canisters script
deploy_canisters_sh=$deploy_canisters_sh"$(GetCanisterDeployCommand ledger "$ledger_args")"

# save files
echo "$dfx_json""$(GetDfxJsonFooter)" > dfx.json
echo "$create_canisters_sh" > create_canisters.sh
echo "$deploy_canisters_sh" > deploy_canisters.sh
