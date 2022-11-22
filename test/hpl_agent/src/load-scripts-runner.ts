import * as fs from 'fs';
import { AggregatorAPI, DelegateFactory, LedgerAPI } from './delegate-factory';
import { AnonymousIdentity, HttpAgent, Identity } from '@dfinity/agent';
import { generateCanisterRequest, indexOfMulti, unwrapCallResult } from './util';
import { Secp256k1KeyIdentity } from '@dfinity/identity';
import * as path from 'path';
import * as os from 'os';
import { Tx } from '../../../.dfx/local/canisters/ledger/ledger.did';

const { spawn } = require('node:child_process');


export class LoadScriptsRunner {

  protected readonly ledgerDelegate: LedgerAPI;
  protected readonly aggregatorDelegates: AggregatorAPI[];

  public resolveIp: string | undefined;

  // UTF-8 encoded string "ingress_expiry" + 0x1B indicator that next value is a 64-bit uint. Used in cbor just before timestamp
  private readonly expiryTimeoutKeyCborSequence = [0x69, 0x6e, 0x67, 0x72, 0x65, 0x73, 0x73, 0x5f, 0x65, 0x78, 0x70, 0x69, 0x72, 0x79, 0x1B];
  // prepare and send this amount of requests. After them cbor-s will be generated from scratch again
  private readonly batchSize = 10000;
  // max amount of requests per curl command. When too low, we have handshake and response waiting overheads,
  // when too big - command can break with unexpected errors like "Url not provided"
  private readonly maxRequestsInOneCurlCommand = 1000;

  private running: boolean = true;

  constructor() {
    const canisterIds = JSON.parse(fs.readFileSync('../../deploy/canister_ids.json', 'utf8'));
    this.ledgerDelegate = DelegateFactory.getLedgerApi(canisterIds.ledger[process.env.DFX_NETWORK]);
    this.aggregatorDelegates = Object.keys(canisterIds)
      .filter(x => /^agg\d+$/.exec(x))
      .map((aggId: string) => DelegateFactory.getAggregatorApi(canisterIds[aggId][process.env.DFX_NETWORK]));
  }

  async start() {
    const userA = new AnonymousIdentity();
    const userB = Secp256k1KeyIdentity.generate();
    const [subaccountA, subaccountB, tokenId] = await this.prepareWallets(userA, userB, 100000000);
    const tx: Tx = {
      map: [{
        owner: userA.getPrincipal(), mints: [],
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
      ]
    };
    const agentA = new HttpAgent({
      identity: userA,
      disableNonce: true,
      fetch: (input, init) => {
        init.keepalive = true;
        return fetch(input, init);
      }
    });
    while (this.running) {
      console.info(new Date(), `Preparing request payloads and curl script`);
      const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), `load_test_${Date.now()}`));
      await this.prepareCurlScript(tmpDir, this.batchSize, agentA, tx);
      const start = Date.now();
      let sent = 0;
      for (let i = 0; i < this.batchSize / this.maxRequestsInOneCurlCommand; i++) {
        const amount = Math.min(
          this.batchSize - this.maxRequestsInOneCurlCommand * i,
          this.maxRequestsInOneCurlCommand
        );
        try {
          await this.runCurl(tmpDir + '/send.sh', this.maxRequestsInOneCurlCommand * i, amount);
          sent += amount;
        } catch (err) {
          // pass
        }
        if (!this.running) {
          break;
        }
      }
      const timeSpent = Date.now() - start;
      console.log(`${sent} TX-s sent to canister in ${timeSpent}ms (${(sent * 1000 / timeSpent).toFixed(2)}TPS)`);
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }

  async stop() {
    this.running = false;
  }

  async prepareWallets(userA: Identity, userB: Identity, tokensToMint: number): Promise<[number, number, number]> {
    console.info(new Date(), 'Registering new token');
    const tokenId = Number(await unwrapCallResult(
      this.ledgerDelegate.createFungibleToken
        .withOptions({ agent: new HttpAgent({ identity: userA }) })
        ()
    ));
    console.info(new Date(), 'Creating 2 subaccounts');
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
    console.info(new Date(), `Minting ${tokensToMint} tokens to user A`);
    await unwrapCallResult(this.ledgerDelegate.processImmediateTx
      .withOptions({ agent: new HttpAgent({ identity: userA }) })
      ({
        map: [{
          owner: userA.getPrincipal(),
          mints: [{ ft: [BigInt(tokenId), BigInt(tokensToMint)] }],
          burns: [],
          inflow: [[BigInt(subaccountA), { ft: [BigInt(tokenId), BigInt(tokensToMint)] }]],
          outflow: [],
          memo: [],
        }]
      }));
    return [subaccountA, subaccountB, tokenId];
  }

  async prepareCurlScript(tmpDir: string, totalTxs: number, agent: HttpAgent, tx: Tx): Promise<void> {
    const aggRequestInfo = await Promise.all(this.aggregatorDelegates.map((agg) => this.prepareCborForAggregator(agg, agent, tx)));
    for (let i = 0; i < totalTxs; i++) {
      const requestInfo = aggRequestInfo[i % aggRequestInfo.length];
      requestInfo.timestamp32_2 += 1; // + 1 nanosecond
      if (requestInfo.timestamp32_2 >= 4294967296) {
        requestInfo.timestamp32_2 -= 4294967296;
        requestInfo.timestamp32_1 += 1;
        // write timestamp32_1 to cbor
        for (let j = 0; j < 4; j++) {
          requestInfo.cbor[requestInfo.timestampOffset + j] = (requestInfo.timestamp32_1 >> (3 - j))
        }
      }
      // write timestamp32_2 to cbor
      for (let j = 0; j < 4; j++) {
        requestInfo.cbor[requestInfo.timestampOffset + j + 4] = (requestInfo.timestamp32_2 >> (3 - j))
      }
      fs.appendFileSync(tmpDir + `/${i}.bin`, Buffer.from(requestInfo.cbor));
    }
    fs.appendFileSync(tmpDir + `/send.sh`, `#!/bin/sh
fname() {
  echo '${tmpDir}/'$1'.bin'
}

aggurl() {
  index=$(expr $1 % ${aggRequestInfo.length})
  ${aggRequestInfo
      .map(
        (rinfo, i) => 'if [ "$index" -eq "' + i + '" ]\n  then\n    echo "' + rinfo.url + '"\n  el'
      )
      .join('')
    }se
    echo "Agg index "$index" out of bounds" >&2
    exit 1
  fi
}

offset=$1
max=$(($2 - 1))
for i in $(seq 0 $max); do
  n=$(($i + $offset))
  arg="--data-binary @$(fname $n) $(aggurl $n)"
if [ "$i" -eq "0" ]
then
  echo "$arg"
else
  echo " -: $arg"
fi
done | xargs -x -n 50000 curl -s -X POST ${this.resolveIp ? '--resolve ic0.app:443:' + this.resolveIp + ' ' : ''}--http2-prior-knowledge -Z --parallel-max 100 --header 'Content-Type: application/cbor'`);
  }

  async runCurl(
    scriptPath: string,
    startIndex: number,
    amount: number,
  ): Promise<void> {
    console.info(new Date(), `Running curl ${startIndex} ${amount}`);
    return new Promise(async (resolve, reject) => {
      const worker = spawn('sh', [scriptPath, startIndex, amount]);
      worker.stdout.on('data', (data) => {
        console.log(`curl stdout: ${data}`);
      });
      worker.stderr.on('data', (data) => {
        console.error(`curl stderr: ${data}`);
        if (data.toString().startsWith('xargs: ')) {
          reject(new Error(data.toString()));
        }
      });
      worker.on('close', (code) => {
        resolve();
      });
    });
  }

  private async prepareCborForAggregator(agg: AggregatorAPI, agent: HttpAgent, tx: Tx):
    Promise<{ url: string, cbor: Uint8Array, timestampOffset: number, timestamp32_1: number, timestamp32_2: number }> {
    const {
      url,
      cborBuffer
    } = await generateCanisterRequest(agg, agent, 'submit', tx);
    const cbor = new Uint8Array(cborBuffer);
    let timestampOffset = indexOfMulti(cbor, this.expiryTimeoutKeyCborSequence);
    if (timestampOffset == -1) {
      throw new Error('Cannot find "ingress_expiry" key in request payload cbor');
    }
    timestampOffset += this.expiryTimeoutKeyCborSequence.length;
    // JS does not support 64-bit uints, such big numbers behave in a very strange way, so keep two 32-bit numbers for timestamp to be on the safe side
    const timestamp32_1 = parseInt(Array.from(cbor)
      .slice(timestampOffset, timestampOffset + 4)
      .map(x => (x < 16 ? '0' : '') + x.toString(16))
      .join(''), 16);
    const timestamp32_2 = parseInt(Array.from(cbor)
      .slice(timestampOffset + 4, timestampOffset + 8)
      .map(x => (x < 16 ? '0' : '') + x.toString(16))
      .join(''), 16);
    return {
      url,
      cbor,
      timestampOffset,
      timestamp32_1,
      timestamp32_2,
    }
  }

}
