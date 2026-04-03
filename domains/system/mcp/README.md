# domains/system/mcp — HWC Infrastructure MCP Server

TypeScript MCP server exposing the nixos-hwc system's declarative NixOS configuration and live runtime state as 38 tools and 5 resources. Connects to Claude Code (stdio), Claude.ai (Streamable HTTP via Tailscale Funnel), and any MCP-compatible client.

## What It Does

**Declarative layer** — Evaluated NixOS config: option values, domain structure, port allocations, host profiles, secret inventory (names only, never values), flake metadata.

**Runtime layer** — Live state: systemd services, podman containers (root socket), disk usage, GPU, Tailscale peers, Prometheus metrics, Caddy routes, Borg backups, mail health, media stack queues.

## Connection Guide

### Claude Code (stdio)

Already configured in `.mcp.json`:

```json
"hwc-infra": {
  "command": "node",
  "args": ["/home/eric/.nixos/domains/system/mcp/src/dist/index.js"],
  "env": {
    "HWC_MCP_TRANSPORT": "stdio",
    "HWC_NIXOS_CONFIG_PATH": "/home/eric/.nixos",
    "HWC_HOSTNAME": "hwc-server"
  }
}
```

Verify: `/mcp` in Claude Code should show `hwc-infra` with 38 tools.

### Claude.ai (Streamable HTTP over Tailscale Funnel)

**Connector URL**: `https://hwc.ocelot-wahoo.ts.net:6243/mcp`

The server runs on hwc-server as a systemd service. Tailscale Funnel on port 6243 exposes it to the public internet, allowing Claude.ai (which connects from Anthropic's infrastructure, not the user's device) to reach it.

**Network path**: Claude.ai → Tailscale Funnel (:6243) → Node.js HTTP (:6200) → MCP Server

Enable in `machines/server/config.nix`:

```nix
hwc.system.mcp.enable = true;
```

Then `nixos-rebuild switch`.

### Manual Testing

```bash
# Health check
curl https://hwc.ocelot-wahoo.ts.net:6243/health

# Full Streamable HTTP handshake
curl -s -o /tmp/body -D /tmp/headers -X POST https://hwc.ocelot-wahoo.ts.net:6243/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'

# Extract session ID, then send tools/list
SESSION=$(awk -F': ' '/^mcp-session-id:/{print $2}' /tmp/headers | tr -d '\r\n')
curl -s -X POST https://hwc.ocelot-wahoo.ts.net:6243/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":2}' | jq '.result.tools | length'
# → 38
```

## Transport Architecture

The server supports three transports, selected by `HWC_MCP_TRANSPORT` env var (or `hwc.system.mcp.transport` NixOS option):

### stdio (Claude Code)

Standard JSON-RPC over stdin/stdout. One `Server` instance for the lifetime of the process. Logs go to stderr.

### Streamable HTTP (Claude.ai — MCP spec 2025-06-18)

The primary remote transport. Served on `POST /mcp` and `GET /mcp`.

**Protocol flow**:
1. Client sends `POST /mcp` with `initialize` JSON-RPC message
2. Server creates a new `Server` + `StreamableHTTPServerTransport` pair (one per session)
3. Server responds with `Content-Type: application/json` containing the initialize result + `Mcp-Session-Id` header
4. Client sends `notifications/initialized` with the session ID
5. Client sends subsequent requests (`tools/list`, `tools/call`, etc.) with the session ID
6. Client can `DELETE /mcp` to close the session

**Critical implementation details** (learned the hard way):

- **One Server+Transport per session**: `StreamableHTTPServerTransport` is NOT reusable across sessions. Each `initialize` creates a fresh pair.
- **`enableJsonResponse: true`**: Without this, the SDK returns `Content-Type: text/event-stream` (SSE format) for ALL responses including `initialize`. Claude.ai expects `application/json` for non-streaming responses. This option makes the transport return JSON for request/response and SSE only for streaming.
- **`onsessioninitialized` callback**: The transport's `sessionId` is `undefined` until `handleRequest` processes the `initialize` message internally. You CANNOT read `transport.sessionId` after `server.connect()` — it's not set yet. Use the `onsessioninitialized` callback to register the session in your map.
- **Pre-parsed body**: Since we read the request body to check for `initialize` before the transport sees it, we pass it as `parsedBody` to `handleRequest(req, res, parsed)` so the transport doesn't try to read the already-consumed stream.
- **CORS headers**: Claude.ai connects from a browser context. Must include `Access-Control-Allow-Origin: *`, `Access-Control-Expose-Headers: Mcp-Session-Id`, and handle `OPTIONS` preflight.
- **`.well-known/*` stubs**: Claude.ai probes `/.well-known/oauth-protected-resource` during connection. Return a clean `404` (empty body) so the client knows auth is not required. Returning our custom JSON 404 could confuse the OAuth discovery logic.

### Legacy SSE (fallback)

`GET /sse` opens an SSE event stream, `POST /messages` sends requests. Single active connection at a time. Kept for compatibility with older MCP clients.

## Network & Exposure

### Port Map

| Port | Listener | Purpose |
|------|----------|---------|
| 6200 | Node.js HTTP server | Internal — all transports land here |
| 6243 | Tailscale Funnel | Public HTTPS — Claude.ai connects here |
| 6243 | Caddy (also) | Tailnet HTTPS — internal Tailscale access |

### Tailscale Funnel Setup

Funnel on port 6243 is configured imperatively (not in NixOS config):

```bash
sudo tailscale funnel --https=6243 --bg 6200
```

This makes `https://hwc.ocelot-wahoo.ts.net:6243/*` publicly accessible, proxying to `http://127.0.0.1:6200`.

**Why port 6243 and not 443**: The Funnel on `:443` has a bug where it returns empty response bodies when proxying to the Node server. Port 6243 works correctly because Tailscale Funnel handles TLS termination and forwards plain HTTP to the Node server without buffering issues.

### Caddy Route

`parts/caddy.nix` creates a Caddy reverse proxy route on `:6243` for Tailnet-internal access (separate from Funnel's public access). It's conditional on SSE transport being enabled and sets `flush_interval = -1` for streaming support.

## Podman Root Socket Access

All 39+ containers on hwc-server run under **root podman**, not rootless. The MCP server runs as user `eric`. To see containers:

1. **`SupplementaryGroups = ["podman"]`** in systemd service config gives the process access to the root podman socket
2. **`/run/podman` in `ReadOnlyPaths`** allows the sandboxed service to reach the socket
3. **All podman commands use `--url unix:///run/podman/podman.sock`** (the `podmanArgs()` helper in `executors/podman.ts` prepends this to every command)

The `podman` group (GID 996) owns `/run/podman/podman.sock` with mode `660`. User `eric` is in the `podman` group.

**Without this**: `podman ps` returns 0 containers (rootless scope), `hwc_monitoring_health_check` reports "0 containers running" (false positive green), and all container tools are useless.

## Security Model

- **Process isolation**: `User = mkForce "eric"`, `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`, kernel protections, namespace restrictions
- **Resource limits**: `MemoryMax=512M`, `CPUQuota=50%`
- **Command execution**: All shell commands go through `safeExec()` using `execFile` (no shell). Arguments are validated against an unsafe pattern (`/[;&|`$(){}]/`) as defense-in-depth, though `execFile` itself prevents shell injection.
- **Secrets**: Tools expose names and metadata only — never decrypt or return secret values
- **Mutations**: Disabled by default. Gated behind `mutations.enable` + per-action allowlist
- **Network**: Node server binds to `127.0.0.1` only. External access requires Tailscale Funnel (authenticated by Tailscale) or Caddy (Tailnet-only)
- **Read-only paths**: `/home/eric/.nixos` (repo), `/nix/store`, `/run/systemd`, `/run/podman`
- **Write paths**: `/tmp`, `/home/eric/400_mail/Maildir`, `/home/eric/.cache`

## Tools (38)

### Configuration (8 tools)

| Tool | Description |
|------|-------------|
| `hwc_config_get_option` | Evaluate any NixOS option via `nix eval` (cached, ~5s first call). Only sees committed changes. |
| `hwc_config_list_domains` | Walk `domains/` directory — returns each domain's subdomains, files, and index.nix presence. |
| `hwc_config_get_port_map` | Parse `routes.nix` for complete port allocation. Optional `filter` param. |
| `hwc_config_get_host_profile` | Parse a machine's config.nix for profiles, domain imports, channel, stateVersion. |
| `hwc_config_search_options` | Grep `domains/` for `mkOption`/`mkEnableOption` matching a query. Returns file, line, name, snippet. |
| `hwc_config_read_file` | Read any file from the nixos-hwc repo (scoped, cannot escape). Supports offset/limit for large files. |
| `hwc_config_list_dir` | List directory contents with file sizes. Optional recursive mode (3 levels max). |
| `hwc_config_flake_metadata` | All flake inputs with name, URL, revision, last-modified date. |

### Services (6 tools)

| Tool | Description |
|------|-------------|
| `hwc_services_status` | Overview of all services, or detail for one. Includes systemd state, uptime, memory, recent logs. |
| `hwc_services_logs` | Journal logs with `since`, `priority`, `grep`, `lines` params. Tries multiple unit name patterns. |
| `hwc_services_container_stats` | Real-time podman container CPU%, memory, net/block IO, PIDs. Tries podman stats, falls back to systemd cgroup data. |
| `hwc_services_show` | Full effective systemd config for a service — security sandbox, paths, resources, environment, dependencies. Key for diagnosing permission issues. |
| `hwc_services_compare_declared_vs_running` | Diff enabled systemd units against running. Finds down or undeclared services. |
| `hwc_services_by_domain` | Map NixOS domains to their services — scans declarative config for systemd/container definitions, cross-references with live state. |

### Monitoring (4 tools)

| Tool | Description |
|------|-------------|
| `hwc_monitoring_health_check` | Traffic-light (green/yellow/red) checks across services, storage, containers. |
| `hwc_monitoring_journal_errors` | Error-level journal entries grouped by unit with counts and messages. |
| `hwc_monitoring_prometheus_query` | PromQL instant or range queries against local Prometheus (:9090). |
| `hwc_monitoring_gpu_status` | NVIDIA GPU via nvidia-smi: temp, utilization, power, processes. |

### Secrets (2 tools)

| Tool | Description |
|------|-------------|
| `hwc_secrets_inventory` | Parse `domains/secrets/declarations/` for all agenix secrets. **Never returns values.** |
| `hwc_secrets_usage_map` | Grep codebase for `age.secrets.*` references — which domains use which secrets. |

### Storage (2 tools)

| Tool | Description |
|------|-------------|
| `hwc_storage_disk_usage` | `df -h` across tiers: root, hot, media, backup. |
| `hwc_storage_backup_status` | Borg backup timer/service status — last run, next scheduled, exit status, recent archive info from journal. |

### Network (3 tools)

| Tool | Description |
|------|-------------|
| `hwc_network_tailscale_status` | Self hostname/IP, all peers with hostname, IP, OS, online state. Funnel ingress nodes collapsed into summary. |
| `hwc_network_caddy_routes` | Live route config from Caddy admin API (:2019). Falls back to parsing routes.nix if admin API returns 403. Supports `check_health` for upstream probing. |
| `hwc_network_vpn_status` | Gluetun VPN public IP and connection state. |

### Mail (10 tools)

| Tool | Description |
|------|-------------|
| `hwc_mail_health` | Reads real health timer state files (`last-healthy`, `first-failure`, cooldowns), Bridge status, sync freshness, notmuch stats. |
| `hwc_mail_search` | Search mail — accepts raw notmuch queries OR saved search names (inbox, action, label:finance, all:work, etc.). |
| `hwc_mail_read` | Read a message or thread by notmuch ID. Returns headers and body text (plain + HTML). |
| `hwc_mail_count` | Count messages matching a notmuch query or saved search name. |
| `hwc_mail_tag` | Three modes: raw (+/-tag), category (exclusive — auto-removes other categories), flag (additive — action/pending). |
| `hwc_mail_actions` | High-level operations: archive, trash, untrash, spam, unspam, read, unread, clear-categories. |
| `hwc_mail_send` | Send email via msmtp. Accounts: proton-hwc, proton-personal, proton-office. Supports cc, bcc, in-reply-to. |
| `hwc_mail_sync` | Trigger full sync cycle (afew move → label copy-back → mbsync → notmuch new). Optional wait. |
| `hwc_mail_accounts` | List configured accounts, identities, saved search names, category/flag tag taxonomy. |
| `hwc_mail_folders` | List Maildir folders with notmuch message counts. Optional account filter. |

### Media (2 tools)

| Tool | Description |
|------|-------------|
| `hwc_media_arr_status` | Hit *arr APIs with agenix API keys for version, health warnings, and queue depth. |
| `hwc_media_download_queue` | SABnzbd queue (reads API key from sabnzbd.ini) and qBittorrent torrent list with state breakdown. |

### Build (1 tool)

| Tool | Description |
|------|-------------|
| `hwc_build_git_status` | Branch, uncommitted changes, unpushed count, recent commits. |

## Resources (5)

| URI | Content |
|-----|---------|
| `hwc://charter` | Full CHARTER.md text |
| `hwc://domain-tree` | JSON tree of all domains and their files |
| `hwc://port-map` | JSON array of all Caddy routes from routes.nix |
| `hwc://secret-inventory` | Secrets grouped by category (system, home, services, infrastructure) |
| `hwc://host-matrix` | All 5 hosts with profiles and domain imports |

## File Layout

```
domains/system/mcp/
  index.nix                        # NixOS module (hwc.system.mcp.* options, systemd service)
  parts/caddy.nix                  # Caddy route: port 6243 → 6200 (conditional on SSE)
  README.md
  src/
    package.json                   # @hwc/infra-mcp, @modelcontextprotocol/sdk ^1.29.0, Node ≥22
    tsconfig.json                  # ES2022, NodeNext, strict
    .gitignore                     # node_modules/ dist/
    src/
      index.ts                     # Entry — server factory, transport routing, session management
      config.ts                    # Loads ServerConfig from HWC_MCP_* env vars
      cache.ts                     # Generic TTL cache (getOrCompute pattern)
      log.ts                       # Structured JSON logger → stderr
      errors.ts                    # Structured error helpers (mcpError, catchError)
      types.ts                     # ToolDef, ToolResult (with McpErrorType), ExecResult, ResourceDef, ServerConfig
      executors/
        shell.ts                   # execFile wrapper — rejects shell metacharacters
        systemd.ts                 # systemctl show/list-units, journalctl
        nix.ts                     # nix eval + nix flake metadata (cached)
        podman.ts                  # podman via root socket (--url unix:///run/podman/podman.sock)
        prometheus.ts              # Prometheus HTTP API (instant + range queries via fetch)
        tailscale.ts               # tailscale status --json
      tools/
        index.ts                   # Aggregates all tool modules into one array
        registry.ts                # ToolRegistry class (name→handler Map)
        config.ts                  # 8 tools — option eval, domains, ports, hosts, search, flake, read file, list dir
        services.ts                # 6 tools — status, logs, container stats, show config, compare, by-domain
        monitoring.ts              # 4 tools — health check, journal errors, prometheus, gpu
        secrets.ts                 # 2 tools — inventory, usage map
        storage.ts                 # 2 tools — disk usage, backup status
        network.ts                 # 3 tools — tailscale, caddy routes, vpn
        mail.ts                    # 10 tools — health, search, read, count, tag, actions, send, sync, accounts, folders
        media.ts                   # 2 tools — arr status, download queue
        build.ts                   # 1 tool — git status
      resources/
        index.ts                   # 5 resources — charter, domain-tree, port-map, secrets, hosts
```

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
hwc.system.mcp.mutations.allowedActions    # list of enum, default ["restart-service" "restart-container" "run-health-check"]
```

## Caching

Expensive operations are cached with configurable TTL:
- **Runtime queries** (systemctl, podman, tailscale): 60s default
- **Declarative queries** (nix eval, flake metadata): 300s default

The `TtlCache` class provides `getOrCompute(key, ttl, fn)` for transparent cache-or-fetch. Cache is in-memory and persists across tool calls within the same server process.

## HTTP Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/mcp` | Streamable HTTP JSON-RPC (initialize, tools/list, tools/call, etc.) |
| GET | `/mcp` | Streamable HTTP SSE stream (server-initiated notifications, requires session) |
| DELETE | `/mcp` | Close a Streamable HTTP session |
| GET | `/sse` | Legacy SSE transport (opens event stream) |
| POST | `/messages` | Legacy SSE message endpoint |
| GET | `/health` | JSON health check (status, tool count, uptime, active sessions) |
| GET | `/.well-known/*` | Clean 404 stubs for OAuth discovery probes |

## Systemd Service

Unit: `hwc-infra-mcp.service`

```bash
# Check status
systemctl status hwc-infra-mcp

# View logs
journalctl -u hwc-infra-mcp -f

# Restart after code changes
npm run build  # in src/
sudo systemctl restart hwc-infra-mcp
```

The service includes: nix, git, systemd, podman, tailscale, curl, jq, borgbackup, coreutils, gawk, gnugrep, procps, util-linux in PATH.

## Troubleshooting

### "0 containers" in health check or container_stats
The podman executor needs root socket access. Check:
- `stat /run/podman/podman.sock` — should be `root:podman 660`
- `id eric` — should include `podman` group
- `index.nix` has `SupplementaryGroups = ["podman"]` and `/run/podman` in `ReadOnlyPaths`

### nix eval returns error
`nix eval` operates on the git store, not the working tree. Uncommitted changes are invisible. Commit first, or use filesystem-based tools (`list_domains`, `search_options`, `get_port_map`) which read the working tree directly.

### Claude.ai "Couldn't reach the MCP server"
1. Check Funnel is running: `sudo tailscale serve status` — should show `:6243 (Funnel on)`
2. Check health from outside: `curl https://hwc.ocelot-wahoo.ts.net:6243/health`
3. Check service is running: `systemctl status hwc-infra-mcp`
4. Check logs for errors: `journalctl -u hwc-infra-mcp --since "5 min ago"`
5. Re-enable Funnel if needed: `sudo tailscale funnel --https=6243 --bg 6200`

### Session errors ("Server not initialized", "Session not found")
The `onsessioninitialized` callback in `index.ts` registers sessions. If sessions aren't persisting, check that the callback is wired correctly and that `enableJsonResponse: true` is set.

### search_options crashes
The `query` parameter is required. Missing it used to cause a TypeError — now it returns a clean error message. Always pass `{"query": "your search term"}`.

## Known Limitations

- **9 tools from spec not implemented** (all Phase 4-6): mutation tools (restart, dry-build, flake-check), diff_hosts, alert_status, library_stats, firewall_rules, sync_status
- **Caddy admin API returns 403**: `caddy_routes` falls back to parsing routes.nix (declarative, not live). Admin API access may need `admin { origins localhost }` in Caddy config.
- **nvidia-smi PATH fallback**: GPU tool tries PATH first, then `/run/current-system/sw/bin/nvidia-smi`. Adding nvidia to the service PATH in index.nix would be more robust.
- **nix eval requires committed changes**: `get_option` and `flake_metadata` use `nix eval` against the git store. Uncommitted changes are invisible.
- **Funnel is imperative**: `sudo tailscale funnel --https=6243 --bg 6200` must be re-run after Tailscale restarts. Not managed by NixOS config.
- **cAdvisor per-container metrics**: Prometheus cAdvisor exporter only reports root cgroup metrics, not per-container. Container stats come from podman/systemd, not Prometheus.

## Dependencies

- Node.js 22 (provided by NixOS module)
- `@modelcontextprotocol/sdk` ^1.29.0 (includes StreamableHTTPServerTransport)
- `@hono/node-server` (transitive dep of SDK, used by Streamable HTTP transport)

## Changelog

- **2026-04-03**: Tool audit — structured errors, descriptions, new tool, HTML stripping:
  - **Structured error responses**: All 38 tools now return `error_type` (NOT_FOUND, PERMISSION_DENIED, VALIDATION_ERROR, TIMEOUT, COMMAND_FAILED, NETWORK_ERROR, UNAVAILABLE, INTERNAL_ERROR), `suggestion` (actionable next step), and `context` (relevant params) on every error path. Added `errors.ts` with `mcpError()` and `catchError()` helpers.
  - **`hwc_services_by_domain`** (new): Maps NixOS domain names to their associated services — scans declarative config for systemd.services and oci-containers definitions, cross-references with live state. Pass a domain (e.g. 'media', 'monitoring') or omit for all.
  - **Tool descriptions rewritten**: All 38 tool descriptions now follow a consistent template: what it does, what it returns, when to use it, limitations, side effects. Write tools annotated with SIDE EFFECT.
  - **HTML stripping**: `hwc_mail_read` now strips HTML tags to plain text instead of returning raw HTML with `[HTML]` prefix. Handles style/script removal, block element conversion, and HTML entity decoding.
  - **Global exception handler**: `index.ts` catch-all now returns structured error format matching tool-level errors.
- **2026-04-03**: LLM self-service tools (3 new, from Claude Code feedback):
  - **`hwc_config_read_file`**: Read any file from the repo (scoped — path-escape protected). Supports offset/limit for large files. The #1 requested tool — lets LLMs read Nix source to diagnose issues.
  - **`hwc_config_list_dir`**: List directory contents with sizes. Optional 3-level recursive mode. Enables LLM codebase navigation.
  - **`hwc_services_show`**: Full `systemctl show` output — security sandbox (ProtectHome, ReadWritePaths, NoNewPrivileges), exec paths, environment, dependencies. Lets LLMs diagnose permission/sandbox issues without terminal access.
- **2026-04-03**: Mail tools expansion (1→10 tools):
  - **`hwc_mail_health` rewrite**: Now consumes real health timer state files (`last-healthy`, `first-failure`, `cooldown-*`) instead of re-implementing checks. Shows ongoing failure duration, alert cooldown state, severity escalation.
  - **`hwc_mail_search`**: Accepts raw notmuch queries OR 38 saved search names (inbox, action, label:finance, all:work, etc.) — auto-resolves names to queries.
  - **`hwc_mail_read`**: Read messages by thread/message ID. Extracts headers + body text from notmuch's nested JSON. Uses `--include-html` for HTML-only messages.
  - **`hwc_mail_count`**: Count messages — supports saved search names.
  - **`hwc_mail_tag`**: Three modes — raw (+/-tag), category (exclusive, auto-removes 13 other categories), flag (additive action/pending). Mirrors aerc's `<Space>m` keybinding behavior.
  - **`hwc_mail_actions`**: High-level semantic ops — archive (+archive -inbox), trash, untrash, spam, read/unread, clear-categories (removes all custom + junk tags).
  - **`hwc_mail_send`**: Send via msmtp with RFC-822 message composition. Supports 3 Proton accounts, cc/bcc, in-reply-to threading.
  - **`hwc_mail_sync`**: Triggers full sync-mail pipeline (afew move → label copy-back → mbsync → notmuch new). Optional wait mode with 2min timeout.
  - **`hwc_mail_accounts`**: Returns configured accounts, identities, saved search names, and full tag taxonomy.
  - **`hwc_mail_folders`**: Walk Maildir tree, enrich with notmuch counts per folder.
  - Tag taxonomy encoded from tags.nix: 14 exclusive categories (business/money/personal/growth/system), 2 additive flags (action/pending).
  - Binary resolution: notmuch/msmtp resolved at runtime (PATH first, then `/etc/profiles/per-user/eric/bin/`).
  - Uses `execFile` directly (not `safeExec`) so notmuch queries with parentheses work.
- **2026-04-03**: Tool audit fixes (12 improvements from Claude.ai audit):
  - **P0**: `container_stats` systemd cgroup fallback when podman stats returns empty; `flake_metadata`/`get_option` use explicit `path:` flake references (fixes CWD-dependent failures)
  - **P1**: `caddy_routes` falls back to routes.nix parsing on 403; `gpu_status` tries `/run/current-system/sw/bin/nvidia-smi` fallback; `health_check` containers uses systemd service list when podman ps fails
  - **P2**: `arr_status` reads agenix API keys + returns health warnings/queue depth; `download_queue` reads SABnzbd API key from config; `backup_status` fixes timer name to `borgbackup-job-hwc-backup` + parses journal for archive info; `search_options` improved name extraction regex
  - **P3**: `mail_health` uses file-based markers instead of `systemctl --user` (which doesn't work from system service); `tailscale_status` collapses funnel-ingress-node entries; `services_logs` fixes always-true condition that prevented unit name fallthrough
  - Fixed `HWC_HOSTNAME` in `.mcp.json` from `hwc-laptop` to `hwc-server`
- **2026-04-03**: Streamable HTTP transport — added MCP spec 2025-06-18 support (`StreamableHTTPServerTransport` with `enableJsonResponse`, session management via `onsessioninitialized`, `.well-known` stubs). Tailscale Funnel on :6243. Claude.ai can now connect.
- **2026-04-02**: Root podman fix — all podman commands route through root socket (`--url unix:///run/podman/podman.sock`), `SupplementaryGroups=["podman"]`, `/run/podman` in ReadOnlyPaths. Container tools now see all 42 root containers.
- **2026-04-02**: Parameter validation — `search_options` no longer crashes on missing `query` param.
- **2026-04-02**: Registered `hwc-infra` in `.mcp.json` for Claude Code stdio access.
- **2026-04-02**: Phase 3 — runtime layer complete. 25 tools, 6 executors, 5 resources.
- **2026-04-02**: Phase 2 — declarative layer. Config tools, secrets tools, 5 MCP resources.
- **2026-04-02**: Phase 1 — foundation. TypeScript scaffolded, 4 initial tools, stdio + SSE, NixOS module.

## Structure

```
domains/system/mcp/
├── index.nix
├── parts/
│   └── caddy.nix
├── README.md
└── src/
    ├── package.json
    ├── tsconfig.json
    ├── .gitignore
    └── src/
        ├── index.ts
        ├── config.ts
        ├── cache.ts
        ├── log.ts
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
        │   ├── media.ts
        │   └── build.ts
        └── resources/
            └── index.ts
```
