import { LedgerAPI } from '../../../.dfx/local/canisters/ledger/ledger.did';
import { AggregatorAPI } from '../../../.dfx/local/canisters/aggregator/aggregator.did';

export class DelegateFactory {

  static getLedgerApi(canisterId: string): LedgerAPI {
    return require('../../../.dfx/local/canisters/ledger')
      .createActor(canisterId, { agentOptions: { host: 'https://ic0.app' } }) as LedgerAPI;
  }

  static getAggregatorApi(canisterId: string): AggregatorAPI {
    return require('../../../.dfx/local/canisters/aggregator')
      .createActor(canisterId, { agentOptions: { host: 'https://ic0.app' } }) as AggregatorAPI;
  }
}
