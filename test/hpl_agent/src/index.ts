import { pathDfxEnvironment } from './util';
import { DelegateFactory } from './delegate-factory';
import * as fs from 'fs';

pathDfxEnvironment();
const canisterIds = JSON.parse(fs.readFileSync('../../deploy/canister_ids.json', 'utf8'));

const ledgerDelegate = DelegateFactory.getLedgerApi(canisterIds.ledger[process.env.DFX_NETWORK]);
const aggregatorDelegates = Object.keys(canisterIds)
  .filter(x => /^agg\d+$/.exec(x))
  .map((aggId: string) => DelegateFactory.getAggregatorApi(canisterIds[aggId][process.env.DFX_NETWORK])
);

setTimeout(async () => {
  console.log(await ledgerDelegate.stats());
}, 0);
