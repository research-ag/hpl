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
    const subaccountA = Number(await unwrapCallResult(
      this.ledgerDelegate.openNewAccounts
        .withOptions({ agent: new HttpAgent({ identity: userA }) })
        (BigInt(1), BigInt(tokenId))
    ));
    const subaccountB = Number(await unwrapCallResult(
      this.ledgerDelegate.openNewAccounts
        .withOptions({ agent: new HttpAgent({ identity: userB }) })
        (BigInt(1), BigInt(tokenId))
    ));
    const mintResult = await unwrapCallResult(this.ledgerDelegate.processImmediateTx
      .withOptions({ agent: new HttpAgent({ identity: userA }) })
      ({
        map: [{
          owner: userA.getPrincipal(),
          mints: [{ ft: [BigInt(tokenId), BigInt(totalTxs)] }],
          burns: [],
          inflow: [[BigInt(subaccountA), { ft: [BigInt(tokenId), BigInt(totalTxs)] }]],
          outflow: [],
          memo: [],
        }], committer: []
      }));
    const tx: Tx = {
      map: [{
        owner: userA.getPrincipal(),
        mints: [],
        burns: [],
        inflow: [],
        outflow: [[BigInt(subaccountA), { ft: [BigInt(tokenId), BigInt(1)] }]],
        memo: [],
      }, {
        owner: userB.getPrincipal(),
        mints: [],
        burns: [],
        inflow: [[BigInt(subaccountB), { ft: [BigInt(tokenId), BigInt(1)] }]],
        outflow: [],
        memo: [],
      },
      ], committer: []
    };
    for (let i = 0; i < totalTxs; i++) {
      this.aggregatorDelegates[i % this.aggregatorDelegates.length].submit
        .withOptions({ agent: new HttpAgent({ identity: userA }) })
        (tx)
        .then((res) => {
          console.log(res);
        });
    }
  }

}
