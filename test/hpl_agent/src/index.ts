import { patchDfxEnvironment } from './util';
import { LoadScriptsRunner } from './load-scripts-runner';
import { createInterface } from 'readline';

patchDfxEnvironment();
const runner = new LoadScriptsRunner();

runner.start().then(() => {
  process.exit(0);
});

const readline = createInterface({
  input: process.stdin,
  output: process.stdout
});
readline.question('Input anything to stop', userRes => {
  console.info('Stopping after finishing iteration...');
  runner.stop().then();
});
