# Hermes Agent

Nous Research's self-improving AI agent (https://github.com/NousResearch/hermes-agent),
deployed natively on hwc-server. Successor to the now-disabled NanoClaw / OpenClaw
modules.

Charter v11.1 native-systemd pattern; mirrors `domains/server/native/ai/lead-scout/`
and `domains/server/native/ai/brain-mcp/` structurally.

## Structure

```
options.nix              # hwc.server.ai.hermes.* schema
index.nix                # OPTIONS / IMPLEMENTATION / VALIDATION
                         # - hermes-install.service (oneshot, sentinel-gated)
                         # - hermes-gateway.service (long-lived, Discord)
                         # - hermes-deploy CLI on PATH
                         # - Caddy port-mode route :19443 -> :8765
                         # - Inline age.secrets declarations
parts/
  bootstrap/             # hermes-deploy TypeScript CLI (hexagonal-lite)
    cli.ts               # inbound shell: argv -> Config -> core
    core.ts              # pure: status / doctor / upgrade / bootstrap
    adapters.ts          # node:fs + node:child_process adapters
    types.ts             # ports (interfaces) + structured error class
    package.json         # @types/node + typescript devDeps (type-check only)
    tsconfig.json        # strict, noEmit
    README.md            # CLI usage + env contract
README.md                # (this file)
```

## Namespace

`hwc.server.ai.hermes.*` — follows the brain-mcp / lead-scout pattern where the
`domains/server/native/` segment is grouping-only (NOT part of the namespace).

## Storage

Single `$HOME` at `/var/lib/hwc/hermes` (via systemd `StateDirectory = "hwc/hermes"`),
owned `eric:users`, 0750. Upstream installer's hardcoded `$HOME/.hermes/`
layout lands inside that state dir cleanly — no symlink trickery needed.

| Path | Contents |
|------|----------|
| `/var/lib/hwc/hermes/.hermes/hermes-agent/` | Code (uv venv, repo clone) |
| `/var/lib/hwc/hermes/.hermes/` | SQLite memory, skills, FTS5, conversations |
| `/var/lib/hwc/hermes/.local/bin/hermes` | Upstream CLI binary |
| `/var/lib/hwc/hermes/.hermes/.installed` | Sentinel — gates the install oneshot |

## Model provider

Hermes drives **DeepSeek V4** (`deepseek-v4-pro`) via the generic `openai-api`
provider against `https://api.deepseek.com/v1`. Because that's a *remote
authenticated* OpenAI-compatible endpoint (not a local llama.cpp/Ollama box),
`model.useApiKey = true` is set: this declares the `hermes-deepseek-key` secret
and injects its contents as `OPENAI_API_KEY` into the gateway and dashboard
ExecStart wrappers, instead of the `sk-local-noauth` placeholder used for local
endpoints. The `claude-code` skill still delegates coding tasks to the local
`claude` CLI on the Max subscription.

## Secrets

- **`hermes-deepseek-key`** — DeepSeek V4 API key, backed by
  `hermes-deepseek-key.age`. Declared only when `model.useApiKey = true`. The
  VALIDATION block fails the build if the .age file is missing.
- **`hermes-anthropic-key`** — reuses existing `nanoclaw-anthropic-key.age` file
  via a re-named logical secret. No re-encryption. Only declared when
  `model.provider = "anthropic"`. Mirrors lead-scout's reuse of
  `datax-discord-webhook.age`.
- **`hermes-discord-bot-token`** — must be created before flipping
  `gateway.discord.enable = true`. The module's VALIDATION block fails the
  build if the .age file is missing.

## Reverse proxy

`hwc.networking.shared.routes` registers `hermes` on port 19443 (verified free
against current routes.nix) forwarding to the loopback dashboard at `:8765`.

## Manual ops

```bash
sudo systemctl start hermes-install      # idempotent — touches sentinel
sudo systemctl status hermes-gateway
journalctl -u hermes-gateway -f

hermes-deploy status                     # JSON
hermes-deploy doctor                     # nixos + upstream hermes doctor
hermes-deploy upgrade                    # hermes update + restart gateway
```

## Changelog

- **2026-06-03** — Reanimated on DeepSeek V4. Added `model.useApiKey` option to
  distinguish a remote authenticated OpenAI-compat endpoint from a local no-auth
  one: when set, the `keyFileSecret` (`hermes-deepseek-key`) is declared and
  injected as `OPENAI_API_KEY` into both the gateway and dashboard ExecStart
  wrappers (dashboard gains `SupplementaryGroups = [ "secrets" ]`). Server config
  flips `enable = true`, `provider = "openai-api"`,
  `baseUrl = https://api.deepseek.com/v1`, `modelName = "deepseek-v4-pro"`.
  Replaces the disabled local LFM2-24B path — a cloud model strong enough for
  29-tool dispatch, at low cost.
- **2026-05-29** — Initial Phase 1 scaffold. Native systemd, install + gateway
  units, TypeScript hermes-deploy CLI (hexagonal-lite, Node 22
  --experimental-strip-types). `gateway.discord.enable` defaults `false`
  pending Discord bot creation + `hermes-discord-bot-token.age` encrypt.
