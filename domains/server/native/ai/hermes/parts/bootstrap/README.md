# hermes-deploy

Control-plane CLI for the Hermes Agent NixOS service. Wired into PATH as
`hermes-deploy` by `domains/server/native/ai/hermes/index.nix`.

## Architecture (hexagonal-lite)

```
cli.ts        # inbound shell — argv parsing, env -> Config, dispatch
core.ts       # pure functions: status / doctor / upgrade / bootstrap
adapters.ts   # outbound adapters: node:fs, node:child_process, agenix readability
types.ts      # Ports (interfaces) the core depends on; structured error class
```

`core.ts` never imports from `node:*`. Swapping `adapters.ts` (e.g. for tests
or a different host) requires no core changes — that's the hexagonal contract.

## Runtime

Runs directly on `nodejs_22` via `--experimental-strip-types` — no `npm install`,
no build step, no node_modules. Type annotations are stripped at execution time;
no transpilation needed.

`package.json` + `tsconfig.json` exist **only** for editor support and ad-hoc
`tsc --noEmit` type-checking. Production execution ignores both files.

```bash
# manual type-check (optional)
cd domains/server/native/ai/hermes/parts/bootstrap
npm install
npx tsc --noEmit
```

## Commands

```
hermes-deploy status      # JSON status of install + gateway + skill counts
hermes-deploy doctor      # Health checks (nixos + upstream hermes doctor)
hermes-deploy upgrade     # hermes update + sudo systemctl restart hermes-gateway
hermes-deploy bootstrap   # Idempotent install check; surfaces next step if missing
```

The actual installation runs as a one-shot systemd service
(`hermes-install.service`), not from this CLI. `bootstrap` only checks state.

## Environment contract

`cli.ts` reads these env vars (set by the Nix wrapper in `index.nix`):

| Var | Source | Purpose |
|-----|--------|---------|
| `HERMES_HOME_DIR` | `cfg.homeDir` | `$HOME` for Hermes; default `/var/lib/hwc/hermes` |
| `HERMES_BIN` | `${homeDir}/.local/bin/hermes` | Upstream binary path |
| `HERMES_INSTALL_SENTINEL` | `${homeDir}/.hermes/.installed` | Idempotency marker |
| `HERMES_MODEL_PROVIDER` | `cfg.model.provider` | One of: anthropic, openai, nous-portal, openrouter |
| `HERMES_MODEL_KEY_FILE` | `/run/agenix/${secret-name}` | agenix-decrypted key path |

Missing or invalid values produce a `CONFIG_INVALID` `HermesDeployError` with
a clear list of which vars are missing.

## Changelog

- 2026-07-06: Rewrote `HermesDeployError` in `types.ts` with explicit field
  declarations + manual constructor assignment, dropping TypeScript's
  parameter-property shorthand (`constructor(public readonly foo: T)`) which
  Node 22's `--experimental-strip-types` (strip-only, no field synthesis) turns
  into a runtime `SyntaxError`. Also extracted `HermesDeployErrorCode` as a named
  union so new codes touch one spot. `tsc --noEmit` stays clean.
