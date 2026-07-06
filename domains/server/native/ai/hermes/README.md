# Hermes Agent

Nous Research's self-improving AI agent (https://github.com/NousResearch/hermes-agent),
deployed on hwc-server as the **official `nousresearch/hermes-agent` Podman
container**. Successor to the disabled NanoClaw / OpenClaw modules.

## Why a container (2026-06-03 re-architecture)

Hermes is built to run as one cohesive app in a single writable `$HOME`, where
the dashboard owns the gateway lifecycle, spawns subprocesses, builds its Node
TUI, and self-updates. The earlier native deployment fragmented it across three
hardened systemd units (`hermes-install`, `hermes-gateway`, `hermes-dashboard`)
with **different environments** — the dashboard had no Discord token, the chat
tab tried to build its Node bundle inside a WebSocket handler on a read-only-ish
tree, and the in-app "restart gateway" button spawned a tokenless rogue gateway.
The official container fixes this structurally: `gateway run` with
`HERMES_DASHBOARD=1` lets **s6-overlay supervise the gateway AND dashboard
together** in one writable `/opt/data`, exactly the environment the app expects.

## Structure

```
index.nix     # OPTIONS / IMPLEMENTATION / VALIDATION
              # - mkInfraContainer "hermes" (cmd: gateway run)
              # - hermes-setup oneshot composes /opt/data/.env from agenix
              # - Caddy vhost route hermes.* -> 127.0.0.1:9119
              # - Caddy static vhost route market-dashboard.* -> dashboard dir
              # - hwc-market-dashboard timer (host) refreshes data.json
              # (deepseek key + discord token mounted by the generated secrets
              #  layer — domains/secrets/, not inline here)
parts/
  bootstrap/  # LEGACY: hermes-deploy TS CLI from the native deployment.
              # Unused by the container module; kept pending cleanup.
README.md     # (this file)
```

## Namespace

`hwc.server.ai.hermes.*` — the `domains/server/native/` path segment is
grouping-only (NOT part of the namespace). The folder name is now a slight
misnomer (it's a container, not native) and is a candidate for relocation to
`domains/server/containers/`.

## Storage

Host dir `${hwc.paths.state}/hermes-agent` (default `/var/lib/hwc/hermes-agent`),
owned `eric:users` 0750, bind-mounted to the container's `/opt/data`:

| Path (in /opt/data) | Contents |
|------|----------|
| `.env` | Runtime-generated secrets (OPENAI_API_KEY, DISCORD_BOT_TOKEN) |
| `config.yaml` | Hermes configuration |
| `sessions/` | Conversation history |
| `memories/` | Persistent memory store |
| `skills/` | Installed skills |
| `logs/` | Runtime logs |

## Model provider

DeepSeek is a **first-class Hermes provider** (`provider: deepseek` in
hermes_cli/auth.py) with its base URL built in; it reads the key from
`DEEPSEEK_API_KEY`. So configuration is two parts:

1. **Key** — `DEEPSEEK_API_KEY` injected from agenix into `/opt/data/.env`.
2. **Model selection** — the image's first-boot `setup` writes
   `config.yaml` with `model.default: anthropic/claude-opus-4.6`,
   `provider: auto`, AND `model.base_url: https://openrouter.ai/api/v1` — the
   last of which forces ALL inference through OpenRouter regardless of provider
   (yielding a 401 since no OpenRouter key is set). None is overridable by env,
   so the container `postStart` pins all three in the persistent config.yaml
   (idempotent, every start): `model.provider = deepseek`,
   `model.default = deepseek-v4-pro`, `model.base_url = https://api.deepseek.com/v1`.

## Secrets

Composed into `/opt/data/.env` by the `hermes-setup` preStart oneshot (gated on
`agenix.service`) — never the Nix store, mirroring the pihole pattern:

- **`hermes-deepseek-key`** → `DEEPSEEK_API_KEY`. Backed by `hermes-deepseek-key.age`.
- **`hermes-discord-bot-token`** → `DISCORD_BOT_TOKEN`. Only consumed when
  `gateway.discord.enable = true`.

Both `age.secrets` mounts are **generated** from `parts/services/*.age` by the
secrets layer (`domains/secrets/`) — this module no longer declares them inline
(removed 2026-06-09). It only reads `config.age.secrets.<name>.path` at preStart.

## Reverse proxy

`hwc.networking.shared.routes` registers `hermes` as a name-based `vhost`
forwarding to the container's dashboard at `127.0.0.1:9119`, with a
`Host: 127.0.0.1` rewrite to satisfy the dashboard's DNS-rebinding defense. URL:
`https://hermes.hwc.iheartwoodcraft.com` (was port `:25443`).

## Manual ops

```bash
sudo systemctl status podman-hermes          # container service
sudo podman logs -f hermes                    # gateway + dashboard (s6) logs
sudo podman exec -it hermes hermes status     # in-container agent status
sudo podman exec -it hermes hermes chat -q "…"  # one-shot agent query
sudo systemctl restart podman-hermes          # restart the whole stack
```

Upgrade = pull a new image tag (bump `hwc.server.ai.hermes.image`, rebuild).

## Market-trials dashboard

Two autonomous paper-trading trials run inside the container via Hermes cron
(`market-daily`/`agg-daily` agents + `*-stops`/`*-weekly` watchdogs), each with
its own ledger under `/opt/data/market-trial` ($10k conservative) and
`/opt/data/market-aggressive` ($5k aggressive). A deterministic engine
(`scripts/market_engine.py`) owns the books and enforces every risk rule; the
LLM only proposes orders.

`hwc.server.ai.hermes.marketDashboard` serves a **read-only** visual dashboard:
- `scripts/dashboard_build.py` (run by the `hwc-market-dashboard` host timer)
  reads both ledgers, marks to live Stooq quotes, derives metrics, and writes
  `data.json` into `marketDashboard.dir`.
- A Caddy `static` vhost route serves that dir; `index.html` is a
  data-driven SPA. URL: `https://market-dashboard.hwc.iheartwoodcraft.com`
  (was port `:25444`; hashed `/assets/*` cached immutably, shell revalidated).

NOTE (Phase B): `scripts/*` and `index.html` currently live in the mutable
`/opt/data` volume, NOT the Nix store — a fresh volume loses them. Folding them
into this module is pending.

## Changelog

- **2026-07-06** — Law 12 child-README sweep — refreshed the `parts/bootstrap/` README (dropped parameter-property shorthand for `--experimental-strip-types` compat). No change to this module's own code.
- **2026-06-09** — Caddy routes migrated to name-based vhosts under the shared
  `*.hwc.iheartwoodcraft.com` wildcard cert: app at `hermes.hwc.iheartwoodcraft.com`
  (was `:25443`) and the market-trials dashboard at
  `market-dashboard.hwc.iheartwoodcraft.com` (was static `:25444`). The `static`
  route now renders through the vhost renderer (assets-only-immutable cache).
  Both dedicated ports closed. See `domains/networking/README.md`.
- **2026-06-09** — Removed the inline `age.secrets` block (`hermes-deepseek-key`
  + `hermes-discord-bot-token`). Both are now mounted by the generated secrets
  layer (`domains/secrets/parts/lib.nix` walks `parts/services/*.age`); this module
  only consumes `config.age.secrets.<name>.path`. No runtime change.
- **2026-06-04** — Added two paper-trading trials + a static dashboard.
  `marketDashboard` option: Caddy `static` route `:25444` over a host dir, plus
  the `hwc-market-dashboard` oneshot+timer (runs `dashboard_build.py` as `eric`
  every 15 min) that regenerates `data.json` from both ledgers. Engine +
  aggregator + SPA live in the container volume (Phase B: fold into Nix).
- **2026-06-03 (pm)** — **Re-architected to the official Podman container.**
  Replaced the native 3-unit systemd deployment (install/gateway/dashboard) with
  `nousresearch/hermes-agent` running `gateway run` + `HERMES_DASHBOARD=1` under
  s6. One writable `/opt/data` volume, secrets composed into `.env` at start via
  `mkInfraContainer` preStart, model via `OPENAI_BASE_URL`/`HERMES_MODEL`. Fixes
  the dashboard chat tab and in-app gateway controls that the fragmented native
  layout broke. `parts/bootstrap/` retained as legacy, unused.
- **2026-06-03 (am)** — Reanimated on DeepSeek V4 (native deployment): added
  `model.useApiKey` to inject `OPENAI_API_KEY` for a remote authenticated
  OpenAI-compat endpoint. Superseded by the container re-architecture same day.
- **2026-05-29** — Initial Phase 1 scaffold. Native systemd, install + gateway
  units, TypeScript hermes-deploy CLI (hexagonal-lite, Node 22
  --experimental-strip-types).
