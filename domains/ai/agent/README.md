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
