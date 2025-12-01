# AI System Enhancement - Deployment Guide

## Overview

This guide covers deploying the enhanced AI system with Open WebUI integration and fixed ai-chat CLI. The enhancements provide both a modern web interface and an improved command-line experience for interacting with your local Ollama instance.

## What's New

### Fixed Issues
- **ai-chat CLI now works properly** - Uses the sophisticated Python tool instead of raw Ollama
- **System context added** - AI knows it's running on your HWC server
- **Conversation history** - All chats are saved to SQLite database

### New Features
- **Open WebUI** - Beautiful web interface for AI interactions
- **Caddy Integration** - Reverse proxy configuration for Tailscale access
- **Enhanced Prompts** - Server-specific context and knowledge

## Architecture

```
User Interfaces:
├── CLI: ai-chat (terminal)
└── Web: Open WebUI (browser via Tailscale)
    ↓
Caddy Reverse Proxy (https://ai.hwc-server.ts.net)
    ↓
Open WebUI Container (port 3000)
    ↓
Ollama API (localhost:11434)
    ↓
Local Models (llama3.2:3b, phi3.5:3.8b, etc.)
```

## Prerequisites

Before deploying, ensure you have:

1. **Ollama running** - Check with `systemctl status podman-ollama`
2. **Podman enabled** - Should already be configured
3. **Caddy running** - For reverse proxy (if using domain access)
4. **Tailscale configured** - For secure remote access (optional)

## Deployment Steps

### Step 1: Review Changes

The following files have been modified or created:

**Modified Files:**
- `domains/home/environment/shell/options.nix` - Fixed ai-chat alias
- `domains/server/ai/local-workflows/options.nix` - Enhanced system prompt

**New Files:**
- `domains/server/ai/open-webui/default.nix` - Module entry point
- `domains/server/ai/open-webui/options.nix` - Configuration options
- `domains/server/ai/open-webui/parts/container.nix` - Podman container config
- `domains/server/ai/open-webui/parts/caddy.nix` - Reverse proxy config

### Step 2: Enable Open WebUI Module

Add to your server configuration (likely `machines/server/config.nix` or `machines/server/home.nix`):

```nix
{
  # Enable Open WebUI
  hwc.server.ai.open-webui = {
    enable = true;
    
    # Optional: Configure domain for Caddy reverse proxy
    domain = "ai.hwc-server.ts.net";  # Or your Tailscale hostname
    
    # Optional: Customize port (default: 3000)
    # port = 3000;
    
    # Optional: Disable auth for single-user setup
    # enableAuth = false;
    
    # Optional: Change default model
    # defaultModel = "llama3.2:3b";
  };
}
```

### Step 3: Import the Module

Ensure the Open WebUI module is imported in your server configuration. Add to the imports list:

```nix
imports = [
  # ... existing imports ...
  ../../domains/server/ai/open-webui
];
```

### Step 4: Configure Caddy (if using domain)

If you set a `domain` in the Open WebUI configuration, you need to ensure your main Caddyfile imports the snippet:

Add to your Caddyfile or Caddy configuration:

```
import /etc/caddy/snippets/*.caddy
```

This will automatically include the Open WebUI reverse proxy configuration.

### Step 5: Rebuild NixOS

Apply the changes:

```bash
# From your NixOS config directory
sudo nixos-rebuild switch

# Or if you have a rebuild script
grebuild
```

### Step 6: Verify Services

Check that everything is running:

```bash
# Check Open WebUI container
sudo podman ps | grep open-webui

# Check Ollama
sudo podman ps | grep ollama

# Check systemd service
systemctl status podman-open-webui

# View logs if needed
sudo podman logs open-webui
```

### Step 7: Access Open WebUI

**Local Access:**
```
http://localhost:3000
```

**Tailscale Access (if configured):**
```
https://ai.hwc-server.ts.net
```

**First-time Setup:**
1. Open the URL in your browser
2. Create an admin account (if auth is enabled)
3. Select your default model
4. Start chatting!

### Step 8: Test ai-chat CLI

After rebuilding, the ai-chat alias should now work properly:

```bash
# Start a chat session
ai-chat

# You should see:
# AI Chat Interface
# Model: phi3.5:3.8b
# Type /help for commands, /quit to exit

# Try asking about your server
>>> What services are running on this server?

# The AI should now have context about your HWC server!
```

## Configuration Options

### Open WebUI Options

All available options in `hwc.server.ai.open-webui`:

```nix
{
  enable = true;                          # Enable Open WebUI
  port = 3000;                            # Internal port
  domain = "ai.hwc-server.ts.net";       # Domain for Caddy
  ollamaEndpoint = "http://127.0.0.1:11434";  # Ollama API
  dataDir = "/var/lib/open-webui";       # Data storage
  enableAuth = true;                      # User authentication
  defaultModel = "phi3.5:3.8b";          # Default model
  enableRAG = true;                       # Document upload/RAG
  ragChunkSize = 1500;                    # RAG chunk size
  ragOverlap = 100;                       # RAG overlap
  imageTag = "latest";                    # Docker image tag
  
  # Extra environment variables
  extraEnv = {
    WEBUI_NAME = "HWC AI Assistant";
  };
}
```

### ai-chat CLI Options

Configured in `hwc.server.ai.local-workflows.chatCli`:

```nix
{
  enable = true;
  model = "phi3.5:3.8b";                 # Default model
  historyFile = "/home/eric/.local/share/ai-chat/history.db";
  maxHistoryLines = 1000;
  systemPrompt = "...";                   # Now includes server context
}
```

## Usage Examples

### CLI Usage

```bash
# Start chat
ai-chat

# Available commands:
/help              # Show all commands
/models            # List available models
/model llama3.2:3b # Switch model
/clear             # Clear conversation context
/history 20        # Show last 20 messages
/export            # Export to markdown
/quit              # Exit

# Example questions:
>>> Check the latest AI journal entry
>>> Why is Jellyfin restarting?
>>> How do I add a new container in NixOS?
>>> Explain this error: [paste error]
```

### Web UI Usage

The Open WebUI provides a rich interface with:

- **Multiple conversations** - Create and manage separate chat threads
- **Model selection** - Switch between models with a dropdown
- **Document upload** - Upload PDFs, text files for RAG
- **Code highlighting** - Syntax highlighting for code blocks
- **Markdown rendering** - Beautiful formatting
- **Export options** - Download conversations
- **Settings** - Customize behavior, appearance, and models

## Troubleshooting

### Open WebUI Container Won't Start

```bash
# Check logs
sudo podman logs open-webui

# Common issues:
# 1. Ollama not running
systemctl status podman-ollama

# 2. Port already in use
sudo netstat -tlnp | grep 3000

# 3. Data directory permissions
ls -la /var/lib/open-webui
```

### ai-chat Shows "Command not found"

```bash
# Check if the script is installed
which ai-chat

# Should show: /nix/store/.../bin/ai-chat

# If not found, rebuild:
sudo nixos-rebuild switch

# Reload shell
source ~/.zshrc
```

### Ollama Connection Errors

```bash
# Test Ollama API
curl http://127.0.0.1:11434/api/tags

# Should return JSON with models list

# If not working:
systemctl status podman-ollama
sudo podman logs ollama
```

### Caddy Reverse Proxy Not Working

```bash
# Check Caddy status
systemctl status caddy

# Check Caddy logs
journalctl -u caddy -f

# Verify snippet is imported
cat /etc/caddy/Caddyfile | grep import

# Test configuration
caddy validate --config /etc/caddy/Caddyfile
```

### Can't Access via Tailscale Domain

```bash
# Check Tailscale status
tailscale status

# Verify hostname
tailscale status | grep hwc-server

# Test DNS resolution
nslookup ai.hwc-server.ts.net

# Check firewall (if domain is not set)
sudo iptables -L -n | grep 3000
```

## Security Considerations

### Network Security

The Open WebUI is configured to be accessible only via:
1. **Localhost** - Direct access on the server
2. **Tailscale** - Secure mesh network (if domain configured)

No external internet access is exposed by default.

### Authentication

If `enableAuth = true` (default):
- Users must create accounts
- Passwords are hashed and stored securely
- Session management via cookies

If `enableAuth = false`:
- Anyone with network access can use the interface
- Recommended only for single-user, isolated networks

### Data Privacy

All data stays local:
- Conversations stored in `/var/lib/open-webui`
- No external API calls
- No telemetry or tracking
- Models run entirely on your hardware

### Command Execution

The current implementation does NOT allow the AI to execute commands. This is intentional for security. If you want to add this capability:

1. Implement a whitelist of safe commands
2. Require user confirmation for each command
3. Use a restricted user account
4. Log all command executions

## Advanced Configuration

### Custom Models

To add more models to Ollama:

```bash
# Pull a new model
ollama pull codellama:13b

# List available models
ollama list

# The model will automatically appear in Open WebUI
```

### RAG Document Upload

To use document upload features:

1. Ensure `enableRAG = true` in config
2. In Open WebUI, click the "+" button
3. Select "Upload Document"
4. Choose PDF, TXT, MD, or other text files
5. The AI will use document content in responses

### Multiple Users

If you want family members to use the system:

1. Keep `enableAuth = true`
2. Each user creates their own account
3. Conversations are private per user
4. All users share the same Ollama models

### Backup and Restore

To backup your conversations and settings:

```bash
# Backup Open WebUI data
sudo tar -czf open-webui-backup.tar.gz /var/lib/open-webui

# Backup ai-chat history
tar -czf ai-chat-backup.tar.gz ~/.local/share/ai-chat

# Restore
sudo tar -xzf open-webui-backup.tar.gz -C /
tar -xzf ai-chat-backup.tar.gz -C ~/
```

## Performance Tuning

### Model Selection

Choose models based on your needs:

- **llama3.2:3b** - Fast, good for quick queries (2GB RAM)
- **phi3.5:3.8b** - Balanced, good default (2.3GB RAM)
- **qwen2.5-coder:3b** - Best for code tasks (2GB RAM)
- **llama3.2:8b** - Better quality, slower (4.7GB RAM)
- **codellama:13b** - Best code quality (7.4GB RAM)

### Container Resources

To limit Open WebUI container resources:

```nix
virtualisation.oci-containers.containers.open-webui = {
  extraOptions = [
    "--memory=2g"
    "--cpus=2"
  ];
};
```

### Ollama Concurrency

Ollama can handle multiple requests. Configure in Ollama settings:

```bash
# Set concurrent requests
OLLAMA_NUM_PARALLEL=4 ollama serve
```

## Maintenance

### Updating Open WebUI

To update to the latest version:

```bash
# Pull latest image
sudo podman pull ghcr.io/open-webui/open-webui:latest

# Restart container
sudo systemctl restart podman-open-webui
```

### Cleaning Up Old Data

```bash
# Clean old conversations (if needed)
# Open WebUI has built-in cleanup in settings

# Clean ai-chat history
sqlite3 ~/.local/share/ai-chat/history.db "DELETE FROM messages WHERE timestamp < date('now', '-90 days');"
```

### Monitoring

Monitor system resources:

```bash
# Container stats
sudo podman stats open-webui ollama

# Disk usage
du -sh /var/lib/open-webui
du -sh ~/.local/share/ai-chat

# Logs
journalctl -u podman-open-webui -f
```

## Next Steps

After deployment, consider:

1. **Test both interfaces** - Try CLI and Web UI
2. **Upload documentation** - Add your NixOS docs for RAG
3. **Customize prompts** - Tailor system prompts to your needs
4. **Add more models** - Experiment with different models
5. **Share with family** - Let others create accounts
6. **Integrate with workflows** - Use AI in your daily admin tasks

## Support and Feedback

If you encounter issues:

1. Check the troubleshooting section above
2. Review logs: `sudo podman logs open-webui`
3. Verify configuration: `nixos-rebuild build` (dry run)
4. Check GitHub issues for Open WebUI

## Summary

You now have a complete local AI system with:

- ✅ Working CLI with conversation history
- ✅ Modern web interface (Open WebUI)
- ✅ Server-specific context and knowledge
- ✅ Secure access via Tailscale
- ✅ Multiple model support
- ✅ Document upload and RAG
- ✅ 100% local, private, and free

Enjoy your enhanced AI assistant!
