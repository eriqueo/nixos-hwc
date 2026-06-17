// Entry point for the NixOS service (esbuild bundles this → server.js). Always
// starts the listener; configFromEnv() does the late binding. http.ts stays
// import-safe (no side effects) so tests can construct the shell without it.

import { createShell, configFromEnv } from "./http.js";

const cfg = configFromEnv();
const shell = createShell(cfg);
shell.server.listen(cfg.port, () => {
  console.log(`refinery engine board on :${cfg.port} (items=${cfg.itemsDir})`);
});

// Two-way brain sync: reconcile the hopper against the vault's _ideas.md on
// boot and on an interval (the vault is the source of truth for raw ideas).
// The /hopper GET also syncs on view; this interval covers the idle case
// (ideas added/removed in the brain while nobody is looking at the board).
if (cfg.vaultDir) {
  const ms = Number(process.env.REFINERY_BRAIN_SYNC_MS || 60000);
  void shell.syncBrain();
  const timer = setInterval(() => void shell.syncBrain(), ms);
  timer.unref();
}
