# domains/system/mcp — HWC Infrastructure MCP Server

TypeScript MCP server that exposes the nixos-hwc system's declarative configuration and live runtime state as tools for Claude Code (stdio) and Claude.ai mobile (SSE over Tailscale).

## What It Does

Two layers of system visibility, accessible from any MCP client:

**Declarative layer** — The evaluated NixOS configuration: option values, domain structure, port allocations, host profiles, secret inventory (names only, never values), and flake metadata.

**Runtime layer** — Live system state: systemd service status, podman container stats, disk usage, GPU utilization, Tailscale peers, Prometheus metrics, Caddy routes, Borg backup status, mail health, and media stack queues.

## Quick Start

### Local (stdio — Claude Code)

```bash
cd domains/system/mcp/src
npm install && npm run build
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | \
  HWC_MCP_TRANSPORT=stdio HWC_NIXOS_CONFIG_PATH=/home/eric/.nixos \
  node dist/index.js 2>/dev/null | jq '.result.tools | length'
# → 25
```

Add to Claude Code MCP config (`~/.claude.json` or `.mcp.json`):

```json
{
  "mcpServers": {
    "hwc-infra": {
      "command": "node",
      "args": ["/home/eric/.nixos/domains/system/mcp/src/dist/index.js"],
      "env": {
        "HWC_MCP_TRANSPORT": "stdio",
        "HWC_NIXOS_CONFIG_PATH": "/home/eric/.nixos",
        "HWC_HOSTNAME": "hwc-laptop"
      }
    }
  }
}
```

### Server (SSE — Claude.ai mobile via Tailscale)

Enable in the server's NixOS config:

```nix
hwc.system.mcp = {
  enable = true;
  # port = 6200;        # default
  # transport = "both"; # default — stdio + SSE
};
```

Then `nixos-rebuild switch`. The SSE endpoint becomes available at `http://127.0.0.1:6200/sse`, proxied by Caddy at `https://hwc.ocelot-wahoo.ts.net:6243/sse`.

Health check: `curl http://localhost:6200/health`

## Tools (25)

### Services

| Tool | Description |
|------|-------------|
| `hwc_services_status` | Status overview of all services, or detail for one. Includes systemd state, uptime, memory, recent logs. Accepts optional `service` name and `type` filter (container/native). |
| `hwc_services_logs` | Journal logs for a service with `since`, `priority`, `grep`, and `lines` parameters. Tries multiple unit name patterns (bare name, podman- prefix, .service suffix). |
| `hwc_services_container_stats` | Real-time podman container resource usage — CPU%, memory, net/block IO, PIDs. Optional `container` filter. |
| `hwc_services_compare_declared_vs_running` | Diffs enabled systemd units against what's actually running. Finds services that are enabled but down, or running but not declared. |

### Build & Git

| Tool | Description |
|------|-------------|
| `hwc_build_git_status` | Branch, uncommitted changes (with status codes), unpushed count, and recent commits. `log_count` parameter controls history depth. |

### Monitoring

| Tool | Description |
|------|-------------|
| `hwc_monitoring_health_check` | Runs checks across `services`, `storage`, and `containers` (or `all`). Returns traffic-light status (green/yellow/red) per component with an overall rollup. |
| `hwc_monitoring_journal_errors` | Error-level journal entries since a given time, grouped by systemd unit with counts and recent messages. Parameters: `since`, `limit`. |
| `hwc_monitoring_prometheus_query` | Execute PromQL queries — `instant` or `range` type. Range queries take `start`, `end`, `step`. Hits the local Prometheus at :9090. |
| `hwc_monitoring_gpu_status` | NVIDIA GPU status via nvidia-smi: name, temperature, GPU/memory utilization, power draw, and which processes are using the GPU. |

### Configuration (Declarative)

| Tool | Description |
|------|-------------|
| `hwc_config_get_option` | Evaluate any NixOS option path via `nix eval` (cached, ~5-15s first call). Only sees committed changes. Example: `hwc.media.jellyfin.enable`. |
| `hwc_config_list_domains` | Walk `domains/` directory — returns each domain's subdomains, .nix files, and whether it has an index.nix. Fast filesystem scan. |
| `hwc_config_get_port_map` | Parse `routes.nix` for the complete port allocation — name, mode (port/subpath/static), external port, path, upstream. Optional `filter` parameter. |
| `hwc_config_get_host_profile` | Parse a machine's config.nix to extract profiles, domain imports, channel (stable/unstable), stateVersion. Required: `host`. |
| `hwc_config_search_options` | Grep all `domains/` .nix files for `mkOption`/`mkEnableOption` matching a keyword. Returns file, line, name, and snippet. |
| `hwc_config_flake_metadata` | Run `nix flake metadata --json` and return all inputs with name, URL, revision (short), and last-modified date. |

### Secrets

| Tool | Description |
|------|-------------|
| `hwc_secrets_inventory` | Parse `domains/secrets/declarations/` for all agenix secrets — name, category, .age file existence, mode, owner, group. **Never returns values.** Optional `category` filter. |
| `hwc_secrets_usage_map` | Grep the entire codebase for `age.secrets.*` references. Returns which domains/files reference which secrets. Optional `service` filter. |

### Storage

| Tool | Description |
|------|-------------|
| `hwc_storage_disk_usage` | `df -h` across storage tiers: root (/), hot (/mnt/hot), media (/mnt/media), backup (/mnt/backup). Parameter: `tier` (or `all`). |
| `hwc_storage_backup_status` | Borg backup systemd timer and service status — last run, next scheduled, exit status. |

### Network

| Tool | Description |
|------|-------------|
| `hwc_network_tailscale_status` | Tailscale status — self hostname/IP, all peers with hostname, IP, OS, online state. |
| `hwc_network_caddy_routes` | Query Caddy's admin API at :2019 for the live route configuration with servers, matchers, and upstream targets. |
| `hwc_network_vpn_status` | Gluetun VPN status — public IP and OpenVPN connection state via the Gluetun HTTP API at :8000. |

### Mail

| Tool | Description |
|------|-------------|
| `hwc_mail_health` | Proton Bridge systemd status, mbsync timer/last run, notmuch message count, recent mail errors from journal. |

### Media

| Tool | Description |
|------|-------------|
| `hwc_media_arr_status` | Hit each *arr service's API (/api/v3/system/status, /api/v3/health). Reports version, running state, health warnings. Parameter: `service` or `all`. |
| `hwc_media_download_queue` | SABnzbd queue (speed, remaining, items) and qBittorrent torrent list (total, active). Parameter: `client` or `all`. |

## Resources (5)

Static or slowly-changing data available as MCP resources (read on demand, not tool calls):

| URI | Content |
|-----|---------|
| `hwc://charter` | Full text of CHARTER.md |
| `hwc://domain-tree` | JSON tree of all domains, their subdirectories and .nix files |
| `hwc://port-map` | JSON array of all Caddy routes parsed from routes.nix |
| `hwc://secret-inventory` | JSON map of secret names grouped by category (system, home, services, infrastructure) |
| `hwc://host-matrix` | JSON map of all 5 hosts with their profiles and domain imports |

## Architecture

### File Layout

```
domains/system/mcp/
  index.nix                        # NixOS module (hwc.system.mcp.* options, systemd service)
  parts/caddy.nix                  # Caddy route: port 6243 → 6200
  README.md
  src/
    package.json                   # @hwc/infra-mcp, ES modules, Node ≥22
    tsconfig.json                  # ES2022, NodeNext, strict
    .gitignore                     # node_modules/ dist/
    src/
      index.ts                     # Entry — registers tools/resources, starts stdio and/or SSE
      config.ts                    # Loads ServerConfig from HWC_MCP_* env vars
      cache.ts                     # Generic TTL cache (getOrCompute pattern)
      log.ts                       # Structured JSON logger → stderr
      types.ts                     # ToolDef, ToolResult, ExecResult, ServerConfig, etc.
      executors/
        shell.ts                   # execFile wrapper — rejects shell metacharacters
        systemd.ts                 # systemctl show/list-units, journalctl
        nix.ts                     # nix eval + nix flake metadata (cached)
        podman.ts                  # podman ps/stats/logs/inspect (JSON format)
        prometheus.ts              # Prometheus HTTP API (instant + range queries via fetch)
        tailscale.ts               # tailscale status --json
      tools/
        index.ts                   # Aggregates all tool modules into one array
        registry.ts                # ToolRegistry class (name→handler Map)
        services.ts                # 4 tools: status, logs, container_stats, compare
        build.ts                   # 1 tool: git_status
        monitoring.ts              # 4 tools: health_check, journal_errors, prometheus, gpu
        config.ts                  # 6 tools: get_option, list_domains, port_map, host_profile, search, flake
        secrets.ts                 # 2 tools: inventory, usage_map
        storage.ts                 # 2 tools: disk_usage, backup_status
        network.ts                 # 3 tools: tailscale, caddy_routes, vpn
        mail.ts                    # 1 tool: health
        media.ts                   # 2 tools: arr_status, download_queue
      resources/
        index.ts                   # 5 resources: charter, domain-tree, port-map, secrets, host-matrix
```

### Transport

The server supports **stdio** (for Claude Code over SSH or local) and **SSE** (for Claude.ai mobile over Tailscale). When `transport = "both"` (default), SSE runs on the configured port while the process can also be invoked via stdio separately.

- **stdio**: Pipe JSON-RPC messages to stdin, read from stdout. Stderr carries structured logs.
- **SSE**: `GET /sse` opens an event stream. `POST /messages` sends requests. `GET /health` returns server status.

### Security

- Runs as user `eric` with `ProtectSystem=strict`, `ProtectHome=read-only`.
- All command execution uses `execFile` (no shell) with metacharacter rejection.
- Secret tools expose names and metadata only — never decrypt or return values.
- Mutations (restart, backup trigger) are disabled by default and gated behind `mutations.enable` + per-action allowlist + `confirm: true` parameter.
- SSE binds to 127.0.0.1; external access goes through Caddy TLS termination on Tailscale.

### Caching

Expensive operations are cached with configurable TTL:
- **Runtime queries** (systemctl, podman, tailscale): 60s default
- **Declarative queries** (nix eval, flake metadata): 300s default

The `TtlCache` class provides `getOrCompute(key, ttl, fn)` for transparent cache-or-fetch.

## NixOS Module Options

```
hwc.system.mcp.enable               # bool, default false
hwc.system.mcp.port                  # port, default 6200
hwc.system.mcp.host                  # string, default "127.0.0.1"
hwc.system.mcp.transport             # "stdio" | "sse" | "both", default "both"
hwc.system.mcp.logLevel              # "debug" | "info" | "warn" | "error", default "info"
hwc.system.mcp.cacheTtl.runtime      # int seconds, default 60
hwc.system.mcp.cacheTtl.declarative  # int seconds, default 300
hwc.system.mcp.mutations.enable      # bool, default false
hwc.system.mcp.mutations.allowedActions  # list of enum, default ["restart-service" "restart-container" "run-health-check"]
```

## Ports

| Port | Purpose |
|------|---------|
| 6200 | SSE server (internal, localhost only) |
| 6243 | Caddy TLS termination (Tailscale HTTPS) |

## Dependencies

- Node.js 22 (provided by NixOS module `path`)
- `@modelcontextprotocol/sdk` ^1.12.1
- System tools in PATH: nix, git, systemd, podman, tailscale, curl, jq, borgbackup, nvidia-smi

## Changelog

- **2026-04-02**: Phase 3 — runtime layer complete. 25 tools, 6 executors, 5 resources. Podman, Prometheus, Tailscale, GPU, mail, media integration.
- **2026-04-02**: Phase 2 — declarative layer. Config tools (nix eval, domain tree, port map, host profiles, option search), secrets tools (inventory, usage map), 5 MCP resources.
- **2026-04-02**: Phase 1 — foundation. TypeScript project scaffolded. 4 initial tools (services status, git status, health check, journal errors). Stdio + SSE dual transport. NixOS module with systemd service.
