# Quick Start - AI System Enhancement

## TL;DR

Your ai-chat is now fixed and you have a new web interface (Open WebUI) for your local AI!

## What Changed

### Fixed
- **ai-chat CLI** now uses the proper Python tool (not raw Ollama)
- **System context** added so AI knows about your server
- **Conversation history** now works properly

### Added
- **Open WebUI** - Beautiful web interface for AI
- **Caddy integration** - Access via Tailscale domain
- **Enhanced prompts** - Server-specific knowledge

## Deploy in 3 Steps

### 1. Enable Open WebUI

Edit your server config (e.g., `machines/server/config.nix`):

```nix
{
  imports = [
    # ... existing imports ...
    ../../domains/server/ai/open-webui
  ];

  hwc.server.ai.open-webui = {
    enable = true;
    domain = "ai.hwc-server.ts.net";  # Optional: your Tailscale hostname
  };
}
```

### 2. Rebuild

```bash
sudo nixos-rebuild switch
```

### 3. Access

**CLI:**
```bash
ai-chat
```

**Web UI:**
- Local: http://localhost:3000
- Tailscale: https://ai.hwc-server.ts.net

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
1. Open in browser
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

# Check port
curl http://localhost:3000
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
  port = 3000;
  domain = "ai.hwc-server.ts.net";
  enableAuth = true;
  defaultModel = "phi3.5:3.8b";
  enableRAG = true;
};
```

## Next Steps

1. ✅ Deploy (follow steps above)
2. 🎯 Test both CLI and Web UI
3. 🎯 Upload your NixOS docs for RAG
4. 🎯 Try different models
5. 🎯 Share with family (create accounts)

## Need Help?

See the full [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md) for:
- Detailed configuration options
- Advanced features
- Security considerations
- Performance tuning
- Maintenance tips

## Summary

You now have:
- ✅ Working CLI with history
- ✅ Modern web interface
- ✅ Server context and knowledge
- ✅ Secure Tailscale access
- ✅ 100% local and private

Enjoy! 🚀
