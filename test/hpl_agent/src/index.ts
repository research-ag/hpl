import { pathDfxEnvironment } from './util';
import { LoadScriptsRunner } from './load-scripts-runner';

pathDfxEnvironment();
const runner = new LoadScriptsRunner();

runner.floodTxs(10).then();
