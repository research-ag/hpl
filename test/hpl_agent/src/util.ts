import * as dotenv from 'dotenv';
import { FuncClass } from '@dfinity/candid/lib/cjs/idl';
import { Principal } from '@dfinity/principal';
import { IDL } from '@dfinity/candid';
import { Agent, AnonymousIdentity, HttpAgent } from '@dfinity/agent';

export const patchDfxEnvironment = () => {
  dotenv.config();
  // make dfx browser js scripts happy
  const g = global as any;
  g.window = g.window || {};
  g.window.fetch = fetch;
  g.window.location = 'https://ic0.app';
}

export const unwrapCallResult = <T>(call: Promise<{ 'ok': T } | { 'err': any }>): Promise<T> => {
  return call.then((res) => {
    if (res['err'] !== undefined) {
      throw new Error(Object.keys(res['err'])[0]);
    } else {
      return res['ok'];
    }
  });
}

/** This canister does not poll canister status and does not return response */
export const callCanisterAsync = async (api: any, agent: Agent | null, methodName: string, ...args): Promise<void> => {
  const { canisterId, effectiveCanisterId, apiAgent } = api[Symbol.for('ic-agent-metadata')].config;
  agent = agent || apiAgent;
  const func: FuncClass = api[Symbol.for('ic-agent-metadata')].service._fields.find(x => x[0] === methodName)[1];
  await agent.call(
    Principal.from(canisterId),
    {
      methodName,
      arg: IDL.encode(func.argTypes, args),
      effectiveCanisterId: effectiveCanisterId !== undefined ? Principal.from(effectiveCanisterId) : Principal.from(canisterId),
    }
  );
}

/** does not make a real http request, but prepares the payload */
export const generateCanisterRequest = async (api: any, agent: HttpAgent | null, methodName: string, ...args): Promise<{ url: string, cborBuffer: ArrayBuffer }> => {
  return new Promise((resolve) => {
    const agentPatched = new HttpAgent({
      identity: agent ? agent['_identity'] : new AnonymousIdentity(),
      disableNonce: true,
      fetch: async (input, init) => {
        resolve({
          url: input.toString(),
          cborBuffer: init.body as ArrayBuffer
        });
        return { ok: true } as any;
      }
    });
    callCanisterAsync(api, agentPatched, methodName, ...args);
  });
}

/** returns index of subarray in array. -1 if not found */
export function indexOfMulti<T>(container: ArrayLike<T>, searchElements: ArrayLike<T>, fromIndex: number = 0): number {
  const index: number = Array.prototype.indexOf.call(container, searchElements[0], fromIndex);
  if(searchElements.length === 1 || index === -1) {
    return index;
  }
  let i = index;
  for (let j = 0; j < searchElements.length && i < container.length; i++, j++) {
    if (container[i] !== searchElements[j]) {
      return indexOfMulti(container, searchElements, index + 1);
    }
  }
  return(i === index + searchElements.length) ? index : -1;
}

