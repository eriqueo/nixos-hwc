# NanoClaw Expansion Guide

This guide explains how to expand NanoClaw's capabilities for server management on hwc-server.

## Current Setup

NanoClaw is configured as a declarative Podman container in the NixOS configuration:

- **Container config**: `domains/ai/nanoclaw/sys.nix`
- **Options**: `domains/ai/nanoclaw/default.nix`
- **Data directory**: `/opt/ai/nanoclaw`
- **Network**: `media-network` (shared with other services)

### Mount Allowlist

The mount allowlist (`sys.nix`) controls what host paths NanoClaw agents can access:

```nix
mountAllowlist = pkgs.writeText "mount-allowlist.json" (builtins.toJSON {
  allowedRoots = [
    { path = "/home/eric/.nixos"; allowReadWrite = true; description = "NixOS config"; }
    { path = "/mnt/media"; allowReadWrite = true; description = "Media library"; }
    { path = "/var/log"; allowReadWrite = false; description = "System logs"; }
    { path = "/home/eric/.claude"; allowReadWrite = true; description = "Claude settings"; }
  ];
  blockedPatterns = [ "password" "secret" "token" ".age" "id_rsa" "id_ed25519" ".gnupg" ];
  nonMainReadOnly = true;
});
```

### Secrets

Secrets are injected via agenix in the pre-start script:
- `nanoclaw-anthropic-key`: Anthropic API key
- `nanoclaw-slack-bot-token`: Slack bot token (if enabled)
- `nanoclaw-slack-app-token`: Slack app token (if enabled)

---

## Expanding Access

### Adding New Mount Paths

To give NanoClaw agents access to additional directories:

1. **Edit `sys.nix`** and add to the `allowedRoots` array:

```nix
{
  path = "/path/on/host";
  allowReadWrite = true;  # or false for read-only
  description = "What this path is for";
}
```

2. **Rebuild NixOS**:
```bash
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server
```

3. **Restart NanoClaw**:
```bash
sudo systemctl restart podman-nanoclaw.service
```

### Creating a New Agent Group

Groups define agent personas with specific capabilities. Each group has its own:
- `CLAUDE.md` - Agent instructions and context
- Workspace folder for persistent storage
- Optional additional container mounts

**Steps:**

1. **Create the group directory**:
```bash
sudo mkdir -p /opt/ai/nanoclaw/groups/my-group
```

2. **Create `CLAUDE.md`** with agent instructions (see `groups/server-admin/CLAUDE.md` for example)

3. **Register the group** in NanoClaw's SQLite database via the main agent, or manually add to `registered_groups` table

4. **For additional mounts**, add `containerConfig` to the group registration:
```json
{
  "containerConfig": {
    "additionalMounts": [
      {
        "hostPath": "/some/host/path",
        "containerPath": "name-in-container",
        "readonly": false
      }
    ]
  }
}
```

---

## n8n Integration

n8n is available on the `media-network` at `http://n8n:5678`.

### Setting Up Webhook Workflows

1. **In n8n** (https://n8n.hwc-server.tail632bf.ts.net):
   - Create a new workflow
   - Add a "Webhook" trigger node
   - Set the HTTP Method (POST recommended)
   - Note the webhook URL path (e.g., `/webhook/my-workflow`)
   - Add your automation nodes
   - Activate the workflow

2. **Trigger from NanoClaw agents**:
```bash
curl -X POST "http://n8n:5678/webhook/my-workflow" \
  -H "Content-Type: application/json" \
  -d '{"action": "do-something", "data": "value"}'
```

### Useful n8n Workflows for Server Management

| Workflow | Description | Trigger |
|----------|-------------|---------|
| `disk-alert` | Alert when disk > 80% | Cron or manual |
| `service-restart` | Restart a systemd service | Webhook |
| `backup-trigger` | Start backup job | Webhook |
| `media-notify` | Notify on new media | Webhook from Sonarr/Radarr |
| `nixos-deploy` | Build and deploy NixOS | Webhook with approval |

### Example: Disk Space Alert Workflow

1. Create webhook: `POST /webhook/check-disk`
2. Add SSH node to run: `df -h / | tail -1 | awk '{print $5}'`
3. Add IF node: If percentage > 80%
4. Add notification (Slack, email, etc.)

---

## Scheduled Tasks

NanoClaw agents can schedule recurring tasks via the `schedule_task` MCP tool:

```javascript
// From within an agent
schedule_task({
  prompt: "Check disk usage and alert if >80%",
  schedule_type: "cron",
  schedule_value: "0 9 * * *"  // Daily at 9am
})
```

### Cron Examples

| Schedule | Cron Expression |
|----------|-----------------|
| Every hour | `0 * * * *` |
| Daily at 9am | `0 9 * * *` |
| Weekly Sunday midnight | `0 0 * * 0` |
| Monthly 1st at noon | `0 12 1 * *` |

---

## Server Management Capabilities

### What NanoClaw Can Do

With the current setup, NanoClaw agents can:

| Capability | How | Notes |
|------------|-----|-------|
| Read/edit NixOS config | `/workspace/extra/nixos/` | Full access |
| Organize media files | `/workspace/extra/media/` | Movies, TV, music |
| Read system logs | `/workspace/extra/logs/` | Read-only |
| Run bash commands | Built-in | With restrictions |
| Trigger n8n workflows | HTTP requests | Via curl |
| Schedule tasks | `schedule_task` MCP tool | Cron or one-time |
| Browse the web | `agent-browser` skill | Headless Chrome |
| Fetch web content | Built-in tools | WebFetch |

### What Requires Manual Setup

| Capability | How to Enable |
|------------|---------------|
| SSH to other machines | Add SSH keys to allowlist or use n8n |
| Database access | Add DB credentials or use n8n |
| Docker/Podman control | Mount socket (security implications) |
| Email sending | Configure SMTP in n8n or add MCP server |
| Smart home control | Set up via n8n webhooks to Home Assistant |

---

## Security Considerations

### Blocked Patterns

The `blockedPatterns` in mount allowlist prevent agents from reading files containing:
- `password`, `secret`, `token`
- `.age` (encrypted secrets)
- `id_rsa`, `id_ed25519` (SSH keys)
- `.gnupg` (GPG keys)

### Non-Main Read-Only

With `nonMainReadOnly: true`, non-main agents get read-only access by default. Only the main channel gets read-write access to mounted paths.

### Recommendations

1. **Don't mount `/run/agenix`** - Contains decrypted secrets
2. **Don't mount home directory root** - Too broad, includes `.ssh/`
3. **Use specific paths** - Mount only what's needed
4. **Review agent output** - Check what agents write before applying

---

## Extending with MCP Servers

NanoClaw supports MCP (Model Context Protocol) servers for additional capabilities.

### Adding an MCP Server

1. **Edit `/opt/ai/nanoclaw/.mcp.json`**:
```json
{
  "servers": {
    "my-server": {
      "command": "path/to/mcp-server",
      "args": ["--some-flag"]
    }
  }
}
```

2. **Restart NanoClaw**:
```bash
sudo systemctl restart podman-nanoclaw.service
```

### Useful MCP Servers

| Server | Purpose |
|--------|---------|
| `mcp-server-git` | Git operations |
| `mcp-server-sqlite` | Database queries |
| `mcp-server-fetch` | Enhanced web fetching |
| `mcp-server-filesystem` | File operations |

---

## Troubleshooting

### Check NanoClaw Logs
```bash
journalctl -u podman-nanoclaw.service -f --no-pager
```

### Check Agent Container Logs
```bash
sudo podman logs nanoclaw-agent-<id>
```

### Verify Mount Allowlist
```bash
cat /opt/ai/nanoclaw/config/mount-allowlist.json | jq
```

### Test n8n Connectivity
```bash
sudo podman exec nanoclaw curl -s http://n8n:5678/healthz
```

### Restart Everything
```bash
sudo systemctl restart podman-nanoclaw.service
```

---

## Quick Reference

### File Locations

| File | Purpose |
|------|---------|
| `domains/ai/nanoclaw/sys.nix` | Container and mount config |
| `domains/ai/nanoclaw/default.nix` | Options definition |
| `/opt/ai/nanoclaw/` | Runtime data directory |
| `/opt/ai/nanoclaw/config/` | Allowlist configs |
| `/opt/ai/nanoclaw/groups/` | Agent group definitions |
| `/opt/ai/nanoclaw/data/sessions/` | Agent session data |

### Services

| Service | Port | URL |
|---------|------|-----|
| NanoClaw | - | Internal container |
| n8n | 5678 | http://n8n:5678 |
| Slack | - | WebSocket (Socket Mode) |

### Commands

```bash
# Rebuild after config changes
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server

# Restart NanoClaw
sudo systemctl restart podman-nanoclaw.service

# Check status
sudo systemctl status podman-nanoclaw.service

# View logs
journalctl -u podman-nanoclaw.service -f --no-pager

# List agent containers
sudo podman ps -a --filter name=nanoclaw-agent
```
