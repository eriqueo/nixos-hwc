# HWC AI Agent

This is a secure FastAPI-based agent that provides a whitelisted HTTP API for command execution.

## Purpose

Provides a safe, auditable interface for Open WebUI to execute system commands without giving it direct shell access.

## Security Features

- **Whitelisted commands only**: Only explicitly allowed commands can be executed
- **Dangerous operator blocking**: Blocks shell operators like `;`, `&&`, pipes, redirects
- **Audit logging**: All requests are logged to `/var/log/hwc-ai/agent-audit.log`
- **Localhost binding**: Only accessible from 127.0.0.1 by default
- **Systemd hardening**: Runs with strict security restrictions
- **Output truncation**: Limits output size to prevent DoS

## Integration Steps

### 1. Add agent import to domains/ai/default.nix

After PRs 1-2 are merged, add this line to the imports in `domains/ai/default.nix`:

```nix
imports = [
  ./options.nix
  ./ollama/default.nix
  ./open-webui/default.nix
  ./local-workflows/default.nix
  ./mcp/default.nix
  ./agent/default.nix  # ADD THIS LINE
];
```

### 2. Enable agent on server

Add to `machines/server/config.nix`:

```nix
hwc.ai.agent = {
  enable = true;
  # Uses defaults: port 6020, localhost binding
};
```

### 3. Configure Open WebUI to use agent

Add to Open WebUI configuration in `machines/server/config.nix`:

```nix
hwc.ai.open-webui = {
  enable = true;
  extraEnv = {
    HWC_AGENT_URL = "http://127.0.0.1:6020";
  };
};
```

### 4. Add Caddy reverse proxy route (optional)

If you want to expose the agent via HTTPS (for remote access), add to `domains/server/routes.nix`:

```nix
{
  name = "ai-agent";
  mode = "subpath";
  path = "/agent";
  upstream = "http://127.0.0.1:6020";
  needsUrlBase = false;
  headers = {};
  ws = false;
}
```

## Testing

### 1. Start the service

```bash
sudo systemctl start hwc-ai-agent
sudo systemctl status hwc-ai-agent
```

### 2. Test allowed command

```bash
curl -sS -X POST http://127.0.0.1:6020/run \
  -H "Content-Type: application/json" \
  -d '{"cmd":"podman ps"}'
```

Expected: JSON response with output

### 3. Test forbidden command

```bash
curl -sS -X POST http://127.0.0.1:6020/run \
  -H "Content-Type: application/json" \
  -d '{"cmd":"rm -rf /"}'
```

Expected: 403 error

### 4. Check audit log

```bash
sudo tail -f /var/log/hwc-ai/agent-audit.log
```

## Configuration

### Allowed Commands

Default allowed commands (can be customized via `hwc.ai.agent.allowedCommands`):

- `podman ps` - List containers
- `podman logs` - View container logs
- `systemctl status` - Check service status
- `journalctl -n 200` - View recent journal entries
- `ls` - List files
- `cat` - Read file contents

### Security Considerations

1. **Localhost only**: Agent binds to 127.0.0.1 by default
2. **Root execution**: Runs as root to access system commands (hardened with systemd)
3. **Audit trail**: All commands are logged with timestamp and remote IP
4. **Rate limiting**: Consider adding rate limiting at the Caddy level if exposed
5. **TLS**: If exposed via Caddy, ensure TLS is enabled

## Open WebUI Integration

To register the agent as a tool in Open WebUI:

1. Access Open WebUI admin panel
2. Go to Tools section
3. Add a new tool with:
   - Name: "System Command"
   - Type: "HTTP POST"
   - URL: `http://127.0.0.1:6020/run`
   - Body: `{"cmd": "{{command}}"}`
   - Headers: `Content-Type: application/json`

Then users can invoke system commands through the chat interface.

> **Stale integration steps.** The "Integration Steps" and "Open WebUI Integration"
> sections above are written against `hwc.ai.open-webui` and `hwc.ai.ollama`, both
> of which have since been removed from this domain (open-webui in the 2026-04-12
> cleanup, the ollama stack on 2026-06-27 — see `domains/ai/README.md`). The agent
> module itself is unchanged; only its documented consumer is gone.

## Structure

```
agent/
├── default.nix        # Import wrapper
├── index.nix          # NixOS module — inline options (Law 10), systemd unit, hardening
├── hwc-ai-agent.py    # FastAPI whitelisted-command service
└── README.md
```

## Changelog

- 2026-08-17: Added `## Structure` + this changelog (Law 12 backfill — the file had neither) and flagged the Open WebUI / ollama integration steps as stale.
- 2026-06-02: `56c1f6c8` — `hwc-ai-agent.py` swept for the server tailnet rename `hwc.ocelot-wahoo.ts.net` → `hwc-server.ocelot-wahoo.ts.net` (3 occurrences). Mechanical.
- 2026-05-21: `4f199955` — deleted the orphan `agent/options.nix` (-21); options are declared inline in `index.nix` per Law 10.
- 2026-04-14: `254f799c` — xps/remote-main sync merge updated `index.nix`.
- 2026-03-06: `0f8f427c` ("options move pt 1") — inlined `options.nix` into `index.nix` (the merge above later re-introduced the orphan).
- 2026-01-18: `af11efbd` — Law 3 path-abstraction sweep, one line in `index.nix`.
- 2026-01-08: `9fa4a532` — `default.nix` renamed to `index.nix` as part of the Phase 1–3 technical-debt cleanup; `b0e138a5` and `734b2894` then adjusted it for the root cleanup and the v10.1 linter.
- 2025-12-04: `27161ccb` — Sprint 5.4 added 12 lines to `hwc-ai-agent.py` alongside the Local Workflows HTTP API.
- 2025-12-03: `e89f1669` — Sprint 5 integration built out `hwc-ai-agent.py` (+69) and reworked the module; `dc627eb0` then fixed service enablement and dependency ordering.
