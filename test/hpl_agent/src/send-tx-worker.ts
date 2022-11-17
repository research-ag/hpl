import { Secp256k1KeyIdentity } from '@dfinity/identity';
import { HttpAgent } from '@dfinity/agent';
import { callCanisterAsync, patchDfxEnvironment } from './util';
import { DelegateFactory } from './delegate-factory';
import { Tx } from '../../../.dfx/local/canisters/ledger/ledger.did';
import * as fs from 'fs';
import { Principal } from '@dfinity/principal';

patchDfxEnvironment();

// supress errors and warnings from dfx
const originalStdErr = console.error;
console.error = ((...args) => {
  if (args[0].indexOf('ExperimentalWarning') > -1) {
    return;
  }
  return originalStdErr(...args);
}).bind(console);
console.warn = () => {};

const [_, __, identity, principalA, subaccountA, principalB, subaccountB, tokenId, txPerAggregator] = process.argv;

const canisterIds = JSON.parse(fs.readFileSync('../../deploy/canister_ids.json', 'utf8'));
const aggregatorDelegates = Object.keys(canisterIds)
  .filter(x => /^agg\d+$/.exec(x))
  .map(aggId => DelegateFactory.getAggregatorApi(canisterIds[aggId][process.env.DFX_NETWORK]));
const totalTxs = +txPerAggregator * aggregatorDelegates.length;

const user = Secp256k1KeyIdentity.fromJSON(identity);
const agentA = new HttpAgent({ identity: user, disableNonce: true });
const tx: Tx = {
  map: [{
    owner: Principal.fromText(principalA),
    mints: [],
    burns: [],
    inflow: [],
    outflow: [[BigInt(subaccountA), { ft: [BigInt(tokenId), BigInt(1)] }]],
    memo: [],
  }, {
    owner: Principal.fromText(principalB),
    mints: [],
    burns: [],
    inflow: [[BigInt(subaccountB), { ft: [BigInt(tokenId), BigInt(1)] }]],
    outflow: [],
    memo: [],
  },
  ]
};

setTimeout(async () => {
  const start = Date.now();
  console.log(`Starting sending Tx-s`);
  for (let i = 0; i < totalTxs; i++) {
    const delegate = aggregatorDelegates[i % aggregatorDelegates.length];
    await callCanisterAsync(delegate, agentA, 'submit', tx);
  }
  const timeSpent = Date.now() - start;
  console.log(`${totalTxs} TX-s sent to canister in ${timeSpent}ms (${(totalTxs * 1000 / timeSpent).toFixed(2)}TPS)`);
});


