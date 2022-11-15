import * as dotenv from 'dotenv';

export const pathDfxEnvironment = () => {
  dotenv.config();
  // make dfx browser js scripts happy
  const g = global as any;
  g.window = g.window || {};
  g.window.fetch = fetch;
  g.window.location = 'https://ic0.app';
}
