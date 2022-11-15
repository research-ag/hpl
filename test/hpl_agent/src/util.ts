import * as dotenv from 'dotenv';

export const pathDfxEnvironment = () => {
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
