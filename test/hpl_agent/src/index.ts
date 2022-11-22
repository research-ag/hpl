import { patchDfxEnvironment } from './util';
import { LoadScriptsRunner } from './load-scripts-runner';

patchDfxEnvironment();
const runner = new LoadScriptsRunner();

const ipArgStr = process.argv.find(x => x.startsWith('--ip='));
runner.resolveIp = ipArgStr && ipArgStr.substring(5);
if (runner.resolveIp) {
  console.info('Resolving ic0 to IP ' + runner.resolveIp);
}

runner.start().then(() => {
  process.exit(0);
});
