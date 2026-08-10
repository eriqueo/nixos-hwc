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

## Structure

```
agent/
├── default.nix       # Import wrapper
├── index.nix         # NixOS module — inline options + systemd unit + hardening
└── hwc-ai-agent.py   # FastAPI whitelisted-command API
```

## Integration Steps

### 1. Import

Already wired: `domains/ai/index.nix` imports `./agent`.

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

## Changelog

- 2026-06-02: Tailnet rename sweep — `hwc.ocelot-wahoo.ts.net` →
  `hwc-server.ocelot-wahoo.ts.net` in `hwc-ai-agent.py` (56c1f6c8).
- 2026-05-21: Deleted the re-introduced `options.nix` orphan (4f199955). Options
  had already been inlined into `index.nix` (Law 10) by the 2026-03-06 options
  move; the file came back through a merge and did nothing.
- 2026-01-18: Law 3 path abstraction in `index.nix` (af11efbd).
- 2026-01-08: `default.nix` → `index.nix` rename (9fa4a532); `default.nix` is now
  the import wrapper.
- 2025-12-04: Local Workflows HTTP API endpoints added to `hwc-ai-agent.py`
  (27161ccb).
