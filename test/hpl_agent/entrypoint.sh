#!/bin/bash
pushd "$(dirname "$0")"

ips=( $(dig +short ic0.app) )
ips_len=${#ips[@]}

processes=8

function cleanup {
  echo "Removing /tmp/load_test_*"
  rm -rf /tmp/load_test_*
}
trap cleanup EXIT

mkdir -p logs
rm -rf logs/worker_*
for i in $(seq 0 $(($processes - 1))); do
  npm run start -- --ip=${ips[$(($i % $ips_len))]} 2>&1 | sed  's/^/worker_'$i': /' | tee logs/worker_$i.log &
done
wait

