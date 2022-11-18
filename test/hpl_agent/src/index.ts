import { patchDfxEnvironment } from './util';
import { LoadScriptsRunner } from './load-scripts-runner';

patchDfxEnvironment();
const runner = new LoadScriptsRunner();

runner.floodTxs(1, 1).then();
