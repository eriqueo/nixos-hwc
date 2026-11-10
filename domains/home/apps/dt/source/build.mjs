import * as esbuild from 'esbuild';
import fs from 'node:fs';

const manifest = JSON.parse(fs.readFileSync(new URL('./package.json', import.meta.url), 'utf-8'));
const output = manifest.bin.dt;

// Bundle CLI entry point — externalize native modules and ink (needs React runtime)
// The source already starts with `#!/usr/bin/env node`; esbuild preserves it on
// line 1 of the bundle, so we MUST NOT add another shebang via `banner` (Node
// rejects a second shebang on line 2 as a SyntaxError).
await esbuild.build({
  entryPoints: ['src/cli/index.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  outfile: output,
  packages: 'external',
  target: 'node20',
  sourcemap: true,
});

fs.chmodSync(output, 0o755);

console.log(`Built ${output}`);
