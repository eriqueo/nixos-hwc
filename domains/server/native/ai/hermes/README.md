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
options.nix   # hwc.server.ai.hermes.* schema (container deployment)
index.nix     # OPTIONS / IMPLEMENTATION / VALIDATION
              # - mkInfraContainer "hermes" (cmd: gateway run)
              # - hermes-setup oneshot composes /opt/data/.env from agenix
              # - Caddy port-mode route :25443 -> 127.0.0.1:9119
              # - age.secrets (deepseek key, discord token)
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

DeepSeek V4 (`deepseek-v4-pro`) via the OpenAI-compatible API, wired through
environment: `OPENAI_BASE_URL=https://api.deepseek.com/v1` and
`HERMES_MODEL=deepseek-v4-pro` (non-secret, in the container `environment`); the
`OPENAI_API_KEY` is injected from agenix at container start.

## Secrets

Composed into `/opt/data/.env` by the `hermes-setup` preStart oneshot (gated on
`agenix.service`) — never the Nix store, mirroring the pihole pattern:

- **`hermes-deepseek-key`** → `OPENAI_API_KEY`. Backed by `hermes-deepseek-key.age`.
- **`hermes-discord-bot-token`** → `DISCORD_BOT_TOKEN`. Only when
  `gateway.discord.enable = true`.

## Reverse proxy

`hwc.networking.shared.routes` registers `hermes` on port **25443** forwarding to
the container's dashboard at `127.0.0.1:9119`, with a `Host: 127.0.0.1` rewrite
to satisfy the dashboard's DNS-rebinding defense. URL:
`https://hwc-server.ocelot-wahoo.ts.net:25443`.

## Manual ops

```bash
sudo systemctl status podman-hermes          # container service
sudo podman logs -f hermes                    # gateway + dashboard (s6) logs
sudo podman exec -it hermes hermes status     # in-container agent status
sudo podman exec -it hermes hermes chat -q "…"  # one-shot agent query
sudo systemctl restart podman-hermes          # restart the whole stack
```

Upgrade = pull a new image tag (bump `hwc.server.ai.hermes.image`, rebuild).

## Changelog

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
