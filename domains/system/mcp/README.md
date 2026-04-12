# domains/system/mcp — HWC MCP Gateway

Unified MCP gateway (v0.3.1) aggregating 138 tools from three sources into a single endpoint. Connects to Claude Code (stdio), Claude.ai (Streamable HTTP via Tailscale Funnel), and any MCP-compatible client.

| Source | Tools | Transport |
|--------|-------|-----------|
| hwc-sys (local, in-process) | 46 | Direct function calls |
| heartwood-mcp (JobTread) | 71 | stdio child process |
| n8n-mcp (workflow automation) | 21 | stdio child process |

## Connection Guide

### Claude Code (stdio)

Configured in `.mcp.json`:

```json
"hwc-sys": {
  "command": "node",
  "args": ["/home/eric/.nixos/domains/system/mcp/src/dist/index.js"],
  "env": {
    "HWC_MCP_TRANSPORT": "stdio",
    "HWC_NIXOS_CONFIG_PATH": "/home/eric/.nixos",
    "HWC_HOSTNAME": "hwc-server"
  }
}
```

In stdio mode, Claude Code spawns the gateway directly. All 129 tools appear as a single server. The gateway spawns heartwood-mcp and n8n-mcp as stdio child processes internally.

### Claude.ai (Streamable HTTP over Tailscale Funnel)

**URL**: `https://hwc.ocelot-wahoo.ts.net/mcp`

All 129 tools (hwc-sys + JT + n8n) are served from this single endpoint. There are no separate `/jt/mcp` or `/n8n/mcp` paths — the unified gateway routes `tools/call` to the correct backend by tool name.

**Network path**: Claude.ai → Tailscale Funnel (:443) → Caddy (:18080) → Node.js (:6200) → MCP Gateway

Enable in `machines/server/config.nix`:

```nix
hwc.system.mcp.enable = true;
```

### Manual Testing

```bash
# Health check (no MCP handshake needed)
curl https://hwc.ocelot-wahoo.ts.net/health | jq .

# Initialize
curl -s -X POST https://hwc.ocelot-wahoo.ts.net/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# List tools (no session ID needed — sessionless mode)
curl -s -X POST https://hwc.ocelot-wahoo.ts.net/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}' | jq '.result.tools | length'
# → 129

# Call a tool
curl -s -X POST https://hwc.ocelot-wahoo.ts.net/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"tools/call","id":3,"params":{"name":"hwc_monitoring_health_check","arguments":{}}}'
```

## Transport Architecture

### v0.3.0 — Sessionless (current)

One long-lived `Server` + `StreamableHTTPServerTransport` pair, created at startup. All requests are handled by the same transport. No session IDs, no session map, no reaper.

```
                                ┌─────────────────────────────┐
  POST /mcp ──────────────────▶ │  Shared Transport            │
                                │  (sessionIdGenerator: undef) │
  POST /mcp ──────────────────▶ │                              │──▶ Server ──▶ BackendManager
                                │  enableJsonResponse: true    │
  POST /mcp ──────────────────▶ │                              │
                                └─────────────────────────────┘
```

Key config:
- `sessionIdGenerator: undefined` — disables SDK session tracking entirely
- `enableJsonResponse: true` — returns `application/json` when client accepts it

### stdio (Claude Code)

Standard JSON-RPC over stdin/stdout. One `Server` instance for the lifetime of the process. Logs go to stderr.

### BackendManager

The `BackendManager` aggregates tools from all sources. When `tools/call` arrives, it routes by tool name:
- hwc-sys tools → local function call via `ToolRegistry`
- heartwood-mcp tools → forwarded over stdio to the child process
- n8n-mcp tools → forwarded over stdio to the child process, then **response-transformed** before returning

Each stdio backend (`StdioBackend`) has a circuit breaker: 5 failures in 2 minutes triggers backoff. The backend auto-reconnects on the next request after cooldown.

### Response Transforms

The `transforms/n8n.ts` module cleans up bloated n8n-mcp responses before they reach the LLM client. Applied automatically in `BackendManager.callTool()` for any tool starting with `n8n_` or named `validate_workflow`/`validate_node`.

**Global transforms** (all n8n responses):
- Flatten `__rl` objects (`{__rl: true, value: X, ...}` → `X`)
- Remove empty objects (`options: {}`, `otherOptions: {}`)
- Strip `webhookId` from non-webhook nodes (Slack nodes etc. have spurious ones)
- Flatten tag arrays (`[{id, name, createdAt, updatedAt}]` → `["name1", "name2"]`)

**Tool-specific transforms**:
- `n8n_get_workflow`, `n8n_update_full_workflow`, `n8n_create_workflow`: remove `activeVersion`, `shared`, version fields, empty `meta`/`staticData`/`pinData`, null `description`, `settings.availableInMCP`/`callerPolicy`
- `n8n_list_workflows`: remove `createdAt`/`updatedAt` per workflow, `isArchived` if false
- `n8n_executions`: remove null `retryOf`/`retrySuccessId`

All transforms are wrapped in try/catch — a failed transform returns the original data unchanged.

## Network & Exposure

### Port Map

| Port | Listener | Purpose |
|------|----------|---------|
| 6200 | Node.js HTTP server | Internal — gateway listens here |
| 18080 | Caddy HTTP backend | Receives Tailscale serve traffic, routes /mcp to :6200 |
| 443 | Tailscale Funnel | Public HTTPS — Claude.ai connects here |
| 6243 | Caddy TLS (port mode) | Tailnet-only HTTPS access |

### Tailscale Funnel Setup

Funnel on port 443 is managed by `tailscale-funnel.service`. It runs `tailscale funnel --https=443 http://127.0.0.1:18080` in foreground mode.

Caddy on :18080 has explicit MCP routes with streaming config:

```
@mcp_routes { path /mcp /mcp/* /health /.well-known/* }
handle @mcp_routes {
  reverse_proxy 127.0.0.1:6200 {
    flush_interval -1
    transport http {
      read_timeout 0
      write_timeout 0
    }
  }
}
```

The `flush_interval -1` is critical — without it, Caddy buffers SSE/streaming responses and Claude.ai sees empty bodies.

## HTTP Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/mcp` | Streamable HTTP JSON-RPC (initialize, tools/list, tools/call, etc.) |
| GET | `/mcp` | SDK-managed SSE notifications (delegated to transport) |
| DELETE | `/mcp` | SDK-managed session close (delegated to transport) |
| GET | `/health` | JSON health check (version, tool count, uptime, backend status, mode) |
| GET | `/.well-known/*` | Clean 404 stubs for OAuth discovery probes |

## Podman Root Socket Access

All containers run under **root podman**. The MCP server runs as user `eric`. To see containers:

1. `SupplementaryGroups = ["podman"]` in systemd service config
2. `/run/podman` in `ReadOnlyPaths`
3. All podman commands use `--url unix:///run/podman/podman.sock`

**Without this**: `podman ps` returns 0 containers (rootless scope) and all container tools are useless.

## Security Model

- **Process isolation**: `User = mkForce "eric"`, `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`, kernel protections
- **Resource limits**: `MemoryMax=512M`, `CPUQuota=50%`
- **Command execution**: All shell commands via `execFile` (no shell). Arguments validated against unsafe patterns as defense-in-depth.
- **Secrets**: Tools expose names and metadata only — never decrypt or return values
- **Mutations**: Disabled by default. Gated behind `mutations.enable` + per-action allowlist
- **Network**: Binds `127.0.0.1` only. External access requires Tailscale Funnel or Caddy

## Troubleshooting

### Claude.ai "Couldn't reach the MCP server"

Check the chain in order:

1. **Service running?** `systemctl status hwc-sys-mcp`
2. **Gateway healthy?** `curl http://127.0.0.1:6200/health`
3. **Caddy up?** `systemctl status caddy`
4. **Funnel running?** `sudo tailscale serve status` — should show `:443 (Funnel on)` → `http://127.0.0.1:18080`
5. **Public reachable?** `curl https://hwc.ocelot-wahoo.ts.net/health`
6. **Tools enumerate?** `curl -X POST https://hwc.ocelot-wahoo.ts.net/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","method":"tools/list","id":1,"params":{}}'`

### Claude.ai connects but tools don't load

Check the response `Content-Type`. It MUST be `application/json` for Claude.ai to parse tools. If you see `text/event-stream`, the transport is missing `enableJsonResponse: true`.

### "Server not initialized" (400) on second POST

The MCP Server hasn't received an `initialize` message. This happens when each request creates a new Server+Transport pair (the broken "stateless" pattern). The Server must be long-lived and shared across requests.

### "0 containers" in health check

Check root podman socket access:
- `stat /run/podman/podman.sock` — should be `root:podman 660`
- `id eric` — should include `podman` group
- `index.nix` has `SupplementaryGroups = ["podman"]` and `/run/podman` in `ReadOnlyPaths`

### nix eval returns stale data

`nix eval` operates on the git store, not the working tree. Uncommitted changes are invisible. Commit first, or use filesystem-based tools (`list_domains`, `search_options`, `get_port_map`) which read the working tree.

### Service running old code after editing TypeScript

The systemd service runs `dist/index.js` (compiled JS), not the TypeScript source. After editing `.ts` files:

```bash
cd domains/system/mcp/src && npx tsc   # compile TS → JS
sudo systemctl restart hwc-sys-mcp      # restart with new JS
```

## What NOT To Do (Lessons from Production Crashes)

### DO NOT create a fresh Server+Transport per HTTP request

This was the v0.2.0→v0.3.0 "stateless" rewrite mistake. The MCP protocol requires `initialize` before any other method on a given Server instance. A fresh Server per request means only `initialize` ever works — `tools/list`, `tools/call`, etc. all fail with "Server not initialized" (400).

**Correct**: One shared Server+Transport at startup, reused across all requests.

### DO NOT use `sessionIdGenerator: () => randomUUID()`

This enables the SDK's internal session tracking map. Over ~1.5 hours of continuous use, sessions accumulate and cause `RangeError: Maximum call stack size exceeded` — a stack overflow crash in the SDK's cleanup/iteration logic.

**Correct**: `sessionIdGenerator: undefined` — disables session tracking entirely. The Server still handles all MCP methods; it just doesn't associate them with sessions.

### DO NOT omit `enableJsonResponse: true`

Without this, the SDK returns `Content-Type: text/event-stream` (SSE format) for ALL responses, wrapping JSON-RPC messages in `event: message\ndata: {...}\n\n`. Claude.ai's MCP proxy expects `application/json` and silently fails to parse SSE-wrapped responses — tools never load.

**Correct**: Always set `enableJsonResponse: true` on `StreamableHTTPServerTransport`.

### DO NOT override the Accept header to force SSE

The codebase has an Accept header fix that adds missing media types for SDK compatibility. Be careful that this doesn't override a client that explicitly requests `application/json`. If the client asks for JSON, the SDK must see that preference so `enableJsonResponse` can honor it.

### DO NOT use `^` version ranges for the MCP SDK

The SDK is pinned to exact `1.12.1` (not `^1.12.1`). Minor SDK updates have broken transport behavior before. Upgrade deliberately with testing.

### DO NOT add session maps, reapers, or ping intervals

The v0.1.0 architecture had session maps with TTL reapers and SSE ping keepalive intervals. This accumulated state caused:
- Session map growth → stack overflow on cleanup iteration
- Reentrant recursion in `cleanupSession()` → crash
- Ping interval leaks when sessions weren't cleaned up properly

The sessionless design eliminates all of these. If you need session awareness in the future, consider a bounded LRU map with hard limits, not unbounded growth.

### DO NOT remove the Caddy `flush_interval -1`

The Caddy reverse proxy on :18080 has `flush_interval -1` for the MCP routes. Without it, Caddy buffers streaming responses. Claude.ai sees `content-length: 0` with empty bodies and can't connect. The `transport http { read_timeout 0; write_timeout 0 }` settings are also required for long-running tool calls.

### DO NOT forget to compile TypeScript before restarting

The service runs `dist/index.js`. Editing `src/*.ts` without running `npx tsc` means the restart loads the old compiled code. The startup log version vs health endpoint version mismatch is a telltale sign.

## Tools (44 hwc-sys)

### Configuration (7)

| Tool | Description |
|------|-------------|
| `hwc_config_get_option` | Evaluate any NixOS option via `nix eval` (cached). Only sees committed changes. |
| `hwc_config_list_domains` | Walk `domains/` directory — subdomains, files, index.nix presence. |
| `hwc_config_get_port_map` | Parse `routes.nix` for complete port allocation. Optional `filter`. |
| `hwc_config_get_host_profile` | Parse a machine's config.nix for profiles and domain imports. |
| `hwc_config_search_options` | Grep `domains/` for `mkOption`/`mkEnableOption` matching a query. |
| `hwc_config_browse` | Read file or list directory in repo (auto-detects). Supports offset/limit, recursive. |
| `hwc_config_flake_metadata` | All flake inputs with name, URL, revision, last-modified. |

### Services (6)

| Tool | Description |
|------|-------------|
| `hwc_services_status` | Overview of all services, or detail for one. State, uptime, memory, logs. |
| `hwc_services_logs` | Journal logs with `since`, `priority`, `grep`, `lines` params. |
| `hwc_services_container_stats` | Podman container CPU%, memory, net/block IO, PIDs. |
| `hwc_services_show` | Full systemd config — sandbox, paths, resources, dependencies. |
| `hwc_services_compare_declared_vs_running` | Diff enabled vs running. Finds down or undeclared services. |
| `hwc_services_by_domain` | Map NixOS domains to their services. |

### Monitoring (4)

| Tool | Description |
|------|-------------|
| `hwc_monitoring_health_check` | Traffic-light checks across services, storage, containers. |
| `hwc_monitoring_journal_errors` | Error-level journal entries grouped by unit. |
| `hwc_monitoring_prometheus_query` | PromQL instant or range queries against Prometheus. |
| `hwc_monitoring_gpu_status` | NVIDIA GPU temp, utilization, power, processes. |

### Secrets (1)

| Tool | Description |
|------|-------------|
| `hwc_secrets_info` | Agenix secret inventory and/or usage map. view=inventory/usage/both. **Never returns values.** |

### Storage (1)

| Tool | Description |
|------|-------------|
| `hwc_storage_status` | Disk usage across tiers and/or Borg backup status. include=all/disk/backup. |

### Network (2)

| Tool | Description |
|------|-------------|
| `hwc_network_tunnel_status` | Tailscale peers and/or Gluetun VPN status. tunnel=tailscale/vpn/all. |
| `hwc_network_caddy_routes` | Live route config from Caddy admin API. Falls back to routes.nix. |

### Mail (9)

| Tool | Description |
|------|-------------|
| `hwc_mail_health` | Health timer state, Bridge status, sync freshness, notmuch stats. |
| `hwc_mail_search` | Search or count mail. Saved search names or raw notmuch queries. count_only flag. |
| `hwc_mail_read` | Read message/thread by notmuch ID. Headers + body text. |
| `hwc_mail_tag` | Tag or act on messages. action (archive/trash/etc), category, flag, or raw tag ops. |
| `hwc_mail_send` | Send via msmtp. Proton accounts, cc/bcc, in-reply-to. |
| `hwc_mail_reply` | Reply to thread with auto-populated recipients, subject, threading headers. |
| `hwc_mail_sync` | Trigger full sync cycle. |
| `hwc_mail_accounts` | Configured accounts, identities, search names, tag taxonomy. |
| `hwc_mail_folders` | Maildir folders with notmuch message counts. |

### Calendar (5)

| Tool | Description |
|------|-------------|
| `hwc_calendar_list` | Events for today, this week, or custom date range. range=today/week/custom. |
| `hwc_calendar_sync` | Trigger immediate vdirsyncer sync to/from iCloud. |
| `hwc_calendar_create` | Create event (timed, all-day, or multi-day). Syncs to iCloud. |
| `hwc_calendar_delete` | Delete event by search (two-step: dry-run then confirm). |
| `hwc_calendar_edit` | Modify event fields (delete + recreate pattern). |

### Website (4)

| Tool | Description |
|------|-------------|
| `hwc_website_list` | List pages or blog posts with frontmatter summaries. |
| `hwc_website_read` | Read page/blog (source=content) or JSON data file (source=data). |
| `hwc_website_write` | Write page/blog (source=content) or JSON data file (source=data). Atomic. |
| `hwc_website_delete` | Soft-delete page/blog to .trash/ directory. |

### CMS (3)

| Tool | Description |
|------|-------------|
| `hwc_cms_browse` | Browse Heartwood business app — read file or list directory (auto-detects). |
| `hwc_cms_write_file` | Write or create file in scoped app. Atomic write. |
| `hwc_cms_delete_file` | Delete file in scoped app. Permanent. |

### Media (1)

| Tool | Description |
|------|-------------|
| `hwc_media_status` | *arr stack status and/or download queue. include=all/arr/downloads. |

### Build (1)

| Tool | Description |
|------|-------------|
| `hwc_build_git_status` | Branch, uncommitted changes, unpushed count, recent commits. |

## Resources (5)

| URI | Content |
|-----|---------|
| `hwc://charter` | Full CHARTER.md text |
| `hwc://domain-tree` | JSON tree of all domains and files |
| `hwc://port-map` | JSON array of Caddy routes from routes.nix |
| `hwc://secret-inventory` | Secrets grouped by category |
| `hwc://host-matrix` | All hosts with profiles and domain imports |

## NixOS Module Options

```
hwc.system.mcp.enable                      # bool, default false
hwc.system.mcp.port                        # port, default 6200
hwc.system.mcp.host                        # string, default "127.0.0.1"
hwc.system.mcp.transport                   # "stdio" | "sse" | "both", default "both"
hwc.system.mcp.logLevel                    # "debug" | "info" | "warn" | "error", default "info"
hwc.system.mcp.cacheTtl.runtime            # int seconds, default 60
hwc.system.mcp.cacheTtl.declarative        # int seconds, default 300
hwc.system.mcp.mutations.enable            # bool, default false
hwc.system.mcp.mutations.allowedActions    # list of enum
```

## File Layout

```
domains/system/mcp/
  index.nix                        # NixOS module (hwc.system.mcp.*, systemd service)
  parts/
    caddy.nix                      # Caddy route: port 6243 → 6200 (tailnet-only)
    jt.nix                         # JobTread backend config options
  README.md
  src/
    package.json                   # @modelcontextprotocol/sdk 1.12.1 (pinned exact)
    tsconfig.json                  # ES2022, NodeNext, strict
    src/
      index.ts                     # Entry — server factory, shared transport, request routing
      config.ts                    # ServerConfig from HWC_MCP_* env vars
      backend-manager.ts           # Aggregates local + stdio backends, routes callTool by name
      stdio-backend.ts             # Spawns MCP child over stdio with circuit breaker
      cache.ts                     # Generic TTL cache (getOrCompute pattern)
      log.ts                       # Structured JSON logger → stderr
      errors.ts                    # Structured error helpers (mcpError, catchError)
      types.ts                     # ToolDef, ToolResult, ExecResult, ResourceDef, ServerConfig
      executors/
        shell.ts                   # execFile wrapper — rejects shell metacharacters
        systemd.ts                 # systemctl show/list-units, journalctl
        nix.ts                     # nix eval + nix flake metadata (cached)
        podman.ts                  # podman via root socket
        prometheus.ts              # Prometheus HTTP API
        tailscale.ts               # tailscale status --json
      tools/
        index.ts                   # Aggregates all tool modules into one array
        registry.ts                # ToolRegistry class (name→handler Map)
        config.ts                  # 8 config tools
        services.ts                # 6 service tools
        monitoring.ts              # 4 monitoring tools
        secrets.ts                 # 2 secret tools
        storage.ts                 # 2 storage tools
        network.ts                 # 3 network tools
        mail.ts                    # 11 mail tools
        calendar.ts                # 7 calendar tools (khal/vdirsyncer → iCloud)
        media.ts                   # 2 media tools
        build.ts                   # 1 git status tool
      transforms/
        n8n.ts                     # N8N response transformer (flatten __rl, tags, trim bloat)
      resources/
        index.ts                   # 5 MCP resources
```

## Systemd Service

Unit: `hwc-sys-mcp.service`

```bash
# Check status
systemctl status hwc-sys-mcp

# View logs
journalctl -u hwc-sys-mcp -f

# Restart after code changes
cd domains/system/mcp/src && npx tsc    # compile TS → JS first!
sudo systemctl restart hwc-sys-mcp
```

PATH includes: nix, git, systemd, podman, tailscale, curl, jq, borgbackup, coreutils, gawk, gnugrep, procps, util-linux, bash, pass, gnupg.

## Caching

- **Runtime queries** (systemctl, podman, tailscale): 60s TTL
- **Declarative queries** (nix eval, flake metadata): 300s TTL

In-memory `TtlCache` with `getOrCompute(key, ttl, fn)`.

## Known Limitations

- **9 tools from spec not implemented** (Phase 4-6): mutation tools, diff_hosts, alert_status, library_stats, firewall_rules, sync_status
- **Caddy admin API returns 403**: `caddy_routes` falls back to parsing routes.nix (declarative, not live)
- **nix eval requires committed changes**: `get_option` and `flake_metadata` use the git store
- **nvidia-smi PATH fallback**: GPU tool tries PATH first, then `/run/current-system/sw/bin/nvidia-smi`

## Changelog

- **2026-04-07**: v0.3.1 — Calendar write tools + mail reply:
  - **hwc_calendar_create**: Create iCloud events via khal (timed, all-day, multi-day). Auto-syncs to iCloud.
  - **hwc_calendar_delete**: Delete events by summary search. Two-step safety (dry-run → confirm).
  - **hwc_calendar_edit**: Modify event fields (delete + recreate pattern). Two-step safety.
  - **hwc_mail_reply**: Reply to email threads with auto-populated recipients, subject, In-Reply-To/References headers. Auto-detects send account from original To/Cc.
  - All write tools trigger vdirsyncer/mail sync after changes.
- **2026-04-07**: Response trimming — reduce token waste in tool outputs:
  - **N8N response transforms** (`transforms/n8n.ts`): global transforms flatten `__rl` objects, remove empty objects, strip spurious `webhookId`, flatten tag arrays. Tool-specific transforms strip `activeVersion`/`shared`/version fields from workflow detail, `createdAt`/`updatedAt` from list results, null retry fields from executions.
  - **hwc_mail_read**: removed `filename` field (Maildir paths are internal plumbing).
  - **hwc_mail_search**: replaced `query: ["id:msgid@host", null]` with `messageId: "msgid@host"` (stripped prefix, dropped null).
  - **hwc_services_container_stats** (overview): slimmed from 9 fields to 3 (`name`, `cpu`, `memory`). Single-container mode retains all fields.
- **2026-04-07**: v0.3.0 — Sessionless transport rewrite (fixes Claude.ai connection):
  - **Root cause**: v0.2.0 "stateless" rewrite created fresh Server+Transport per POST. Only `initialize` worked; all subsequent requests got "Server not initialized" (400). Claude.ai couldn't load tools.
  - **Fix**: One long-lived shared Server+Transport with `sessionIdGenerator: undefined` (no session tracking) and `enableJsonResponse: true` (JSON responses for Claude.ai).
  - **Why sessionless**: The SDK's session map accumulates entries over time. After ~1.5 hours, cleanup iteration triggers `RangeError: Maximum call stack size exceeded`. Disabling sessions entirely eliminates this class of crash.
  - **Accept header**: Retained the fix that ensures both `application/json` and `text/event-stream` are in the Accept header (SDK rejects requests missing either).
  - **Removed**: `randomUUID` import, `readBody()` helper, `isInitializeRequest()` helper, per-request Server/Transport creation.
  - **SDK pinned**: `@modelcontextprotocol/sdk` locked to exact `1.12.1` (was `^1.12.1`).
- **2026-04-04**: v0.2.0 — Unified gateway with stdio backends:
  - **Architecture**: Replaced HTTP reverse proxies (`/jt/*`, `/n8n/*`) with stdio child processes. BackendManager aggregates all tools into a single `/mcp` endpoint.
  - **Circuit breaker**: StdioBackend tracks failures; 5 in 2 minutes triggers exponential backoff.
  - **129 tools**: hwc-sys (38) + heartwood-mcp (70) + n8n-mcp (21) served from one endpoint.
- **2026-04-03**: Streamable HTTP transport, Tailscale Funnel, Caddy :443 conflict resolution, SSE keepalive, session management, n8n proxy, tool audit, mail tools expansion (1→10), LLM self-service tools, structured errors.
- **2026-04-02**: Root podman fix, parameter validation, `.mcp.json` registration, Phase 1-3 foundation.

## Structure

```
domains/system/mcp/
├── index.nix
├── parts/
│   ├── caddy.nix
│   └── jt.nix
├── README.md
└── src/
    ├── package.json
    ├── tsconfig.json
    ├── .gitignore
    └── src/
        ├── index.ts
        ├── config.ts
        ├── backend-manager.ts
        ├── stdio-backend.ts
        ├── cache.ts
        ├── log.ts
        ├── errors.ts
        ├── types.ts
        ├── executors/
        │   ├── shell.ts
        │   ├── systemd.ts
        │   ├── nix.ts
        │   ├── podman.ts
        │   ├── prometheus.ts
        │   └── tailscale.ts
        ├── tools/
        │   ├── index.ts
        │   ├── registry.ts
        │   ├── config.ts
        │   ├── services.ts
        │   ├── monitoring.ts
        │   ├── secrets.ts
        │   ├── storage.ts
        │   ├── network.ts
        │   ├── mail.ts
        │   ├── calendar.ts
        │   ├── media.ts
        │   └── build.ts
        ├── transforms/
        │   └── n8n.ts
        └── resources/
            └── index.ts
```
