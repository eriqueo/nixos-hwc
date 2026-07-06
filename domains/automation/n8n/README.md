# domains/automation/n8n/

## Purpose

n8n workflow automation platform running as a Podman container. Handles alert routing, webhook processing, business integrations (JobTread, Slack), and general workflow automation. Exposed via Cloudflare Tunnel (`n8n.heartwoodcraft.me`) for external webhook access.

## Boundaries

- **Manages**: n8n container, secret injection, firewall rules, MCP HTTP bridge
- **Does NOT manage**: Workflow JSON definitions (→ `parts/workflows/`), estimator integration (→ `parts/estimator-integration/`), MQTT broker (→ `domains/automation/mqtt/`), Cloudflare Tunnel public ingress (→ `domains/networking/cloudflared`)

## Structure

```
domains/automation/n8n/
├── index.nix          # Option definitions, firewall rules, container orchestration
├── sys.nix            # Container definition, env file generation, tmpfiles
├── README.md          # This file
└── parts/
    ├── estimator-integration/  # Estimator webhook integration
    │   └── README.md
    └── workflows/              # n8n workflow JSON definitions
        └── README.md
```

## Namespace

`hwc.automation.n8n.*`

## Configuration

```nix
hwc.automation.n8n = {
  enable = true;
  image = "docker.io/n8nio/n8n:latest";
  port = 5678;
  webhookUrl = "https://n8n.heartwoodcraft.me";
  dataDir = "/var/lib/hwc/n8n";
  timezone = "America/Denver";

  database.type = "sqlite";

  encryption.keyFile = config.age.secrets.n8n-encryption-key.path;

  secrets = {
    estimatorApiKeyFile = config.age.secrets.estimator-api-key.path;
    jobtreadGrantKeyFile = config.age.secrets.jobtread-grant-key.path;
    slackWebhookUrlFile = config.age.secrets.slack-webhook-url.path;
    anthropicApiKeyFile = config.age.secrets.anthropic-api-key.path;
  };

  owner = {
    email = "eric@iheartwoodcraft.com";
    firstName = "Eric";
    lastName = "Okeefe";
    passwordHashFile = config.age.secrets.n8n-owner-password-hash.path;
  };

};
```

## MCP Access

n8n's MCP tooling now runs as a **stdio backend of the unified gateway** (`hwc-sys-mcp`, port 6200) — see `domains/system/mcp/`. The old standalone HTTP bridge (port 6201, `mcp-bridge.nix`) was removed 2026-07-05.

### Namespace

`hwc.automation.n8n.mcpBridge.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the MCP HTTP bridge |
| `port` | port | 6201 | HTTP listen port |
| `host` | string | "127.0.0.1" | Bind address |
| `authTokenFile` | path or null | null | agenix secret for AUTH_TOKEN (uses static internal token if null) |

### Claude.ai Connection URL

```
https://mcp.heartwoodcraft.me/n8n/mcp
```

### Testing

```bash
# Health check (through public Cloudflare Tunnel)
curl -s https://mcp.heartwoodcraft.me/health | jq .

# n8n MCP initialize
curl -s -X POST https://mcp.heartwoodcraft.me/n8n/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# Verify clean .well-known 404
curl -s -w "HTTP: %{http_code}\n" https://mcp.heartwoodcraft.me/n8n/.well-known/oauth-authorization-server
# → HTTP: 404 (empty body)
```

## Dependencies

- **agenix secrets**: encryption key, owner password hash, various API keys, n8n-api-key (for MCP bridge)
- **Cloudflare Tunnel** (`domains/networking/cloudflared`) — public ingress for `n8n.heartwoodcraft.me` and `mcp.heartwoodcraft.me`
- **hwc-sys-mcp** — Express server proxies `/n8n/*` to the MCP bridge

## Access

| Endpoint | URL |
|----------|-----|
| n8n UI (internal) | `http://127.0.0.1:5678` |
| n8n UI (tailnet) | `https://hwc-server.ocelot-wahoo.ts.net:2443` (Caddy port route) |
| n8n webhook (public) | `https://n8n.heartwoodcraft.me/webhook/...` |
| n8n MCP (Claude.ai) | `https://mcp.heartwoodcraft.me/n8n/mcp` |
| n8n MCP (internal) | `http://127.0.0.1:6201/mcp` |

## Systemd Units

- `podman-n8n.service` — main n8n container (generates secrets env file in preStart)
- `hwc-n8n-mcp.service` — MCP HTTP bridge (npm install + patch + run)
- `hwc-n8n-mcp-env.service` — generates bridge env file from agenix secrets

## Changelog

- 2026-07-05: Removed `mcp-bridge/` module (audit 2.2: never enabled; superseded by n8n-mcp running as a stdio backend of the unified `hwc-sys-mcp` gateway). README's stale bridge architecture section replaced.

- 2026-05-31: Add `hwcLeadsHmacFile` secret option + `NODE_FUNCTION_ALLOW_BUILTIN=crypto` container env so the thin-shell `work_calculator_lead` workflow can HMAC-sign POST /leads at the n8n boundary. Phase 2.6 Move A cutover — calculator-lead workflow shrunk from 23 nodes to 4 (Webhook → Build LeadInput → POST /leads → Respond). v2 fat workflow archived at `domains/business/leads/parts/workflows/work_calculator_lead-v2-fat-archive-2026-05-31.json` as rollback.
- 2026-05-22: Remove Tailscale Funnel — public access migrated to Cloudflare Tunnel (n8n.heartwoodcraft.me). Remove funnel options and systemd services. Caddy :18080/:10080 listeners removed.
- 2026-04-03: Rename `n8n-mcp-bridge.service` → `hwc-n8n-mcp.service`, `n8n-mcp-bridge-env` → `hwc-n8n-mcp-env` (consistent MCP naming)
- 2026-04-03: Funnel moved to :443 — Caddy :18080 backend routes `/n8n/*` to Express :6200, which proxies to bridge :6201. URLs updated from `:8443` to no port suffix.
- 2026-04-03: Add MCP bridge — n8n-mcp HTTP bridge on port 6201 with declarative npm install, JSON response patch, Express proxy route, and Claude.ai connection via Tailscale Funnel
- 2026-03-25: Created README per Law 12
