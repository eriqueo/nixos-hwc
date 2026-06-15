// Entry point for the NixOS service (esbuild bundles this → server.js). Always
// starts the listener; configFromEnv() does the late binding. http.ts stays
// import-safe (no side effects) so tests can construct the shell without it.

import { createShell, configFromEnv } from "./http.js";

const cfg = configFromEnv();
const { server } = createShell(cfg);
server.listen(cfg.port, () => {
  console.log(`refinery engine board on :${cfg.port} (items=${cfg.itemsDir})`);
});
