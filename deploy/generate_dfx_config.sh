#!/bin/sh
pushd "$(dirname "$0")"

# build dfx.json

# canister definition in dfx.json. Arguments are: alias name, module name
printJsonEntry () {
  printf '    "%s": {
      "wasm": "../.dfx/local/canisters/%s/%s.wasm",
      "candid": "../.dfx/local/canisters/%s/%s.did",
      "type": "custom"
    }' $1 $2 $2 $2 $2
  }
# header
cat >dfx.json <<-END
{
  "canisters": {
END
# entries
i=0
for p in $(cat wallet_principals.txt); do
  if [ "$i" -eq "0" ]
  then
    printJsonEntry ledger ledger >>dfx.json
  else
    echo , >>dfx.json
    printJsonEntry agg$((i-1)) aggregator >>dfx.json
  fi
  i=$((++i))
done
# footer 
cat >>dfx.json <<-END

  },
  "defaults": {
    "build": {
      "args": "",
      "packtool": ""
    }
  },
  "dfx": "0.12.0",
  "version": 1
}
END

# create and deploy scripts

alias canister_id="dfx canister --network ic id"
# printCreateCmd <wallet_principal> <canister_alias>
printCreateCmd () { printf 'dfx_create --wallet %s --with-cycles 100000000000 %s' "$1" "$2" ; }
# printDeployCmd <canister_alias> <deploy_argument>
printDeployCmd() { printf 'dfx_deploy %s --argument=%s\n' "$1" "$2" ; }

# header
cat >create_canisters.sh <<-END
#!/bin/sh
pushd "\$(dirname "\$0")"

network=ic
alias cid="dfx canister --network \$network id"
alias dfx_create="dfx canister --network \$network create"

END

cat >deploy_canisters.sh <<-END
#!/bin/sh
pushd "\$(dirname "\$0")"

network=ic
alias cid="dfx canister --network \$network id"
alias dfx_deploy="dfx deploy --network \$network --no-wallet"

END

# entries
i=0
# arguments for ledger canister deploy: will be filled with aggregator id-s in a loop below
ledger_arg='"(vec { '
for wallet in $(cat wallet_principals.txt); do
  if [ "$i" -eq "0" ]
  then
    # do the ledger, but only the create command, not the deploy command
    # the deploy command is done after the for loop (its argument is 
    # constructed in this loop)
    printCreateCmd $wallet ledger >>create_canisters.sh
  else
    # do one aggregator 
    N=$((i-1))
    alias=agg$N
    # add create and deploy commands
    deploy_arg=$(printf '"(principal \\"$(cid ledger)\\", %s, 65536)"' $N)
    echo "" >>create_canisters.sh
    printCreateCmd $wallet $alias >>create_canisters.sh
    printDeployCmd $alias "$deploy_arg" >>deploy_canisters.sh
    # add one element to the ledger's deploy argument
    ledger_arg=$ledger_arg$(printf 'principal \\"$(cid %s)\\"; ' $alias)
  fi
  i=$((++i))
done
# finalize ledger's deploy argument and add the deploy command
ledger_arg=$ledger_arg'})"'
printDeployCmd ledger "$ledger_arg" >>deploy_canisters.sh

echo "\n\npopd" >>create_canisters.sh
echo "\npopd" >>deploy_canisters.sh
chmod +x create_canisters.sh deploy_canisters.sh
popd