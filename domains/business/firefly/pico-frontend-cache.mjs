import fs from 'node:fs/promises'
import { createRequire } from 'node:module'
const require = createRequire('/usr/local/lib/node_modules/npm/package.json')
const cacache = require('cacache')
// Bounded: one hash-verified archive in memory at a time. Fail on any write error.
for (const file of (await fs.readdir('/tmp/npm-packages')).sort()) {
  await cacache.put('/tmp/npm-cache/_cacache', `hwc:${file}`, await fs.readFile(`/tmp/npm-packages/${file}`))
}
