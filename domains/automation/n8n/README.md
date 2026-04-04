# domains/automation/n8n/

## Purpose

n8n workflow automation platform running as a Podman container. Handles alert routing, webhook processing, business integrations (JobTread, Slack), and general workflow automation. Exposed via Tailscale Funnel for external access.

## Boundaries

- **Manages**: n8n container, Tailscale Funnel exposure, secret injection, firewall rules
- **Does NOT manage**: Workflow JSON definitions (→ `parts/workflows/`), estimator integration (→ `parts/estimator-integration/`), MQTT broker (→ `domains/automation/mqtt/`)

## Structure

```
domains/automation/n8n/
├── index.nix          # Option definitions, firewall, Tailscale Funnel services
├── sys.nix            # Container definition, env file generation, tmpfiles
├── mcp-bridge.nix     # MCP HTTP bridge for Claude.ai access (port 6201)
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
  webhookUrl = "https://hwc.ocelot-wahoo.ts.net";
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

  funnel = {
    enable = true;
    port = 10000;   # n8n UI direct access; MCP bridge uses :443 via Caddy :18080
  };

  # MCP bridge — exposes n8n workflows to Claude.ai
  mcpBridge.enable = true;
};
```

## MCP Bridge (Claude.ai Access)

The MCP bridge exposes n8n's workflows as MCP tools via Streamable HTTP, allowing Claude.ai to trigger and manage workflows.

### Architecture

```
Claude.ai → Tailscale Funnel :443 → Caddy :18080 → hwc-sys Express :6200 → /n8n/* proxy → n8n-mcp :6201 → n8n API :5678
```

### How it works

1. **n8n-mcp bridge** (`hwc-n8n-mcp.service`) runs the `n8n-mcp` npm package in HTTP mode on port 6201. It connects to n8n's REST API on port 5678 and translates n8n operations into MCP tools.

2. **hwc-sys Express proxy** (`hwc-sys-mcp.service`) reverse-proxies `/n8n/*` requests to port 6201, injecting the internal auth token via `Authorization` header. It also returns clean empty 404s for `/n8n/.well-known/*` probes that Claude.ai makes during connection setup.

3. **Tailscale Funnel** (`tailscale-funnel.service`) exposes port 443 publicly, forwarding to Caddy on port 18080, which routes `/n8n/*` to Express on port 6200.

### Declarative setup

All components are fully declarative in NixOS config:

- `mcp-bridge.nix` — bridge service, npm install + patch (ExecStartPre), env file generation
- `domains/system/mcp/index.nix` — Express proxy env vars (`HWC_N8N_MCP_PORT`, `HWC_N8N_MCP_AUTH_TOKEN`)
- `domains/system/mcp/src/src/index.ts` — `/n8n/*` proxy route and `.well-known` stub
- Tailscale Funnel on port 443 (declarative: `tailscale-funnel.service` in `domains/system/networking.nix`)

The npm package (`n8n-mcp@2.40.5`) is installed and patched automatically on service start via `ExecStartPre`. The patch adds `enableJsonResponse: true` to the StreamableHTTPServerTransport constructor, which is required for Claude.ai compatibility (expects `application/json`, not `text/event-stream`).

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
https://hwc.ocelot-wahoo.ts.net/n8n/mcp
```

### Testing

```bash
# Health check (through public Funnel)
curl -s https://hwc.ocelot-wahoo.ts.net/health | jq .

# n8n MCP initialize
curl -s -X POST https://hwc.ocelot-wahoo.ts.net/n8n/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# Verify clean .well-known 404
curl -s -w "HTTP: %{http_code}\n" https://hwc.ocelot-wahoo.ts.net/n8n/.well-known/oauth-authorization-server
# → HTTP: 404 (empty body)
```

## Dependencies

- **agenix secrets**: encryption key, owner password hash, various API keys, n8n-api-key (for MCP bridge)
- **Tailscale** — Funnel services expose n8n publicly on ports 10000 and 443
- **hwc-sys-mcp** — Express server proxies `/n8n/*` to the MCP bridge

## Access

| Endpoint | URL |
|----------|-----|
| n8n UI (internal) | `http://127.0.0.1:5678` |
| n8n UI (Funnel) | `https://hwc.ocelot-wahoo.ts.net:10000` |
| n8n MCP (Claude.ai) | `https://hwc.ocelot-wahoo.ts.net/n8n/mcp` |
| n8n MCP (internal) | `http://127.0.0.1:6201/mcp` |

## Systemd Units

- `podman-n8n.service` — main n8n container (generates secrets env file in preStart)
- `hwc-n8n-mcp.service` — MCP HTTP bridge (npm install + patch + run)
- `hwc-n8n-mcp-env.service` — generates bridge env file from agenix secrets
- `tailscale-funnel-n8n.service` — public Funnel on port 10000

## Changelog

- 2026-04-03: Rename `n8n-mcp-bridge.service` → `hwc-n8n-mcp.service`, `n8n-mcp-bridge-env` → `hwc-n8n-mcp-env` (consistent MCP naming)
- 2026-04-03: Funnel moved to :443 — Caddy :18080 backend routes `/n8n/*` to Express :6200, which proxies to bridge :6201. URLs updated from `:8443` to no port suffix.
- 2026-04-03: Add MCP bridge — n8n-mcp HTTP bridge on port 6201 with declarative npm install, JSON response patch, Express proxy route, and Claude.ai connection via Tailscale Funnel
- 2026-03-25: Created README per Law 12
