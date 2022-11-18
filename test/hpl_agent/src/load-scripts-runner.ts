import * as fs from 'fs';
import { AggregatorAPI, DelegateFactory, LedgerAPI } from './delegate-factory';
import { AnonymousIdentity, HttpAgent } from '@dfinity/agent';
import { unwrapCallResult } from './util';
import { Secp256k1KeyIdentity } from '@dfinity/identity';

const { spawn } = require('node:child_process');


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

  async floodTxs(txPerWorkerAggregator: number, workersAmount: number) {
    const totalTxs = txPerWorkerAggregator * workersAmount * this.aggregatorDelegates.length;
    const userA = new AnonymousIdentity();
    const userB = Secp256k1KeyIdentity.generate();
    console.info('Registering new token');
    const tokenId = Number(await unwrapCallResult(
      this.ledgerDelegate.createFungibleToken
        .withOptions({ agent: new HttpAgent({ identity: userA }) })
        ()
    ));
    console.info('Creating 2 subaccounts');
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
    console.info(`Minting ${totalTxs} tokens to user A`);
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
        }]
      }));
    console.info(`Spawning Tx sender workers....`);

    const start = Date.now();
    await Promise.all(Array(workersAmount).fill(null).map(_ => this.runWorker(userA, userB, subaccountA, subaccountB, tokenId, txPerWorkerAggregator)));
    const timeSpent = Date.now() - start;
    console.log(`${totalTxs} TX-s sent to canister in ${timeSpent}ms (${(totalTxs * 1000 / timeSpent).toFixed(2)}TPS)`);
  }

  async runWorker(
    userA: AnonymousIdentity,
    userB: Secp256k1KeyIdentity,
    subaccountA: number,
    subaccountB: number,
    tokenId: number,
    txPerAggregator: number,
  ): Promise<void> {
    return new Promise(async (resolve) => {
      const worker = spawn('ts-node', [
        'src/send-tx-worker.ts',
        userA.getPrincipal().toText(),
        subaccountA,
        userB.getPrincipal().toText(),
        subaccountB,
        tokenId,
        txPerAggregator,
      ]);
      worker.stdout.on('data', (data) => {
        console.log(`worker stdout: ${data}`);
      });
      worker.stderr.on('data', (data) => {
        console.error(`worker stderr: ${data}`);
      });
      worker.on('close', (code) => {
        resolve();
      });
    });
  }

}
