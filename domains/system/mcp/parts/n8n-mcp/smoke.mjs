// Exercise the deployed entry point, including its bundled node database.
// The Nix sandbox supplies no network or API key; this only reads node docs.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const [entry, node] = process.argv.slice(2);
const require = createRequire(entry);
const { Client } = await import(pathToFileURL(require.resolve('@modelcontextprotocol/sdk/client/index.js')));
const { StdioClientTransport } = await import(pathToFileURL(require.resolve('@modelcontextprotocol/sdk/client/stdio.js')));
const client = new Client({ name: 'nix-offline-check', version: '1.0.0' });
const transport = new StdioClientTransport({
  command: node, args: [entry], stderr: 'inherit',
  env: { HOME: process.env.TMPDIR, MCP_MODE: 'stdio', NODE_ENV: 'production',
    LOG_LEVEL: 'error', N8N_MCP_TELEMETRY_DISABLED: 'true' },
});
try {
  await client.connect(transport);
  const { tools } = await client.listTools();
  assert(tools.some(t => t.name === 'get_node'), 'node documentation tool missing');
  const result = await client.callTool({ name: 'get_node', arguments: { nodeType: 'nodes-base.httpRequest' } });
  assert(!result.isError, JSON.stringify(result));
  assert(JSON.stringify(result).includes('httpRequest'), 'bundled node database not consumed');
  console.log(`n8n backend: ${tools.length} tools; bundled HTTP Request node read offline`);
} finally {
  await client.close();
}
