import * as fs from 'fs';
import { AggregatorAPI, DelegateFactory, LedgerAPI } from './delegate-factory';
import { HttpAgent } from '@dfinity/agent';
import { unwrapCallResult } from './util';
import { Secp256k1KeyIdentity } from '@dfinity/identity';
import { Tx } from '../../../.dfx/local/canisters/ledger/ledger.did';


export class LoadScriptsRunner {

  protected readonly ledgerDelegate: LedgerAPI;
  protected readonly aggregatorDelegates: AggregatorAPI[];

  constructor() {
    const canisterIds = JSON.parse(fs.readFileSync('../../deploy/canister_ids.json', 'utf8'));
    this.ledgerDelegate = DelegateFactory.getLedgerApi(canisterIds.ledger[process.env.DFX_NETWORK]);
    this.aggregatorDelegates = Object.keys(canisterIds)
      .filter(x => /^agg\d+$/.exec(x))
      .map((aggId: string) => DelegateFactory.getAggregatorApi(canisterIds[aggId][process.env.DFX_NETWORK])
      );
  }

  async floodTxs(txPerAggregator: number) {
    const totalTxs = txPerAggregator * this.aggregatorDelegates.length;
    const userA = Secp256k1KeyIdentity.generate();
    const userB = Secp256k1KeyIdentity.generate();
    const tokenId = Number(await unwrapCallResult(
      this.ledgerDelegate.createFungibleToken
        .withOptions({ agent: new HttpAgent({ identity: userA }) })
        ()
    ));
    // TODO create subaccounts for users A and B
    const mintResult = await unwrapCallResult(this.ledgerDelegate.processImmediateTx({ map: [{
      owner: userA.getPrincipal(),
      mints: [{ ft: [BigInt(tokenId), BigInt(totalTxs)]}],
      burns: [],
      inflow: [],
      outflow: [],
      memo: [],
    }], committer: [] }));
    console.log(mintResult);
    const tx: Tx = { map: [{
        owner: userA.getPrincipal(),
        mints: [],
        burns: [],
        inflow: [],
        outflow: [[BigInt(0), { ft: [BigInt(tokenId), BigInt(1)]}]],
        memo: [],
      },{
        owner: userB.getPrincipal(),
        mints: [],
        burns: [],
        inflow: [[BigInt(0), { ft: [BigInt(tokenId), BigInt(1)]}]],
        outflow: [],
        memo: [],
      },
      ], committer: [] };
    // TODO bomb with tx
  }

}
