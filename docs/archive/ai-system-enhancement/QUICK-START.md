# Quick Start - AI System Enhancement (v2)

## TL;DR

Your ai-chat is now fixed and you have a new web interface (Open WebUI) for your local Ollama!

## What Changed

### Fixed
- **ai-chat CLI** now uses the proper Python tool (not raw Ollama)
- **System context** added so AI knows about your server
- **Conversation history** now works properly

### Added
- **Open WebUI** - Beautiful web interface for AI
- **Centralized routing** - Integrated with your existing routing system
- **Subpath access** - Available at `/ai` on your Tailscale domain

## Deploy in 2 Steps

### 1. Enable Open WebUI

The module is already imported via `profiles/ai.nix`. Just enable it in your server config:

```nix
# In machines/server/config.nix or home.nix
hwc.server.ai.open-webui = {
  enable = true;
};
```

### 2. Rebuild

```bash
sudo nixos-rebuild switch
```

## Access

**CLI:**
```bash
ai-chat
```

**Web UI:**
- Tailscale: https://hwc-server.ocelot-wahoo.ts.net/ai
- (Subpath mode via centralized routing)

## First Use

### CLI
```bash
ai-chat

>>> What services are running on this server?
# AI now knows it's on your HWC server!

>>> /help
# See all commands

>>> /models
# List available models

>>> /quit
# Exit
```

### Web UI
1. Open https://hwc-server.ocelot-wahoo.ts.net/ai
2. Create account (if auth enabled)
3. Select model
4. Start chatting!

## Key Features

### CLI Commands
- `/models` - List models
- `/model llama3.2:3b` - Switch model
- `/history 20` - Show recent messages
- `/export` - Save conversation to markdown
- `/clear` - Clear context
- `/quit` - Exit

### Web UI Features
- Multiple conversations
- Model switching
- Document upload (RAG)
- Code highlighting
- Markdown rendering
- Export conversations

## Troubleshooting

### ai-chat not found
```bash
sudo nixos-rebuild switch
source ~/.zshrc
```

### Open WebUI not starting
```bash
sudo podman logs open-webui
systemctl status podman-ollama
```

### Can't access web UI
```bash
# Check if running
sudo podman ps | grep open-webui

# Check routing
# The route is defined in domains/server/routes.nix
```

## Configuration Options

### Minimal (defaults)
```nix
hwc.server.ai.open-webui.enable = true;
```

### Custom
```nix
hwc.server.ai.open-webui = {
  enable = true;
  port = 3000;  # Internal container port
  enableAuth = true;
  defaultModel = "phi3.5:3.8b";
  enableRAG = true;
};
```

## Architecture

Open WebUI integrates with your centralized routing system:

```
User Request
    ↓
https://hwc-server.ocelot-wahoo.ts.net/ai
    ↓
Caddy (centralized routing via routes.nix)
    ↓
Open WebUI Container (localhost:3000)
    ↓
Ollama API (localhost:11434)
    ↓
Local Models
```

## Next Steps

1. ✅ Deploy (follow steps above)
2. 🎯 Test both CLI and Web UI
3. 🎯 Upload your NixOS docs for RAG
4. 🎯 Try different models
5. 🎯 Share with family (create accounts)

## Summary

You now have:
- ✅ Working CLI with history
- ✅ Modern web interface
- ✅ Server context and knowledge
- ✅ Integrated with centralized routing
- ✅ 100% local and private

Enjoy! 🚀
