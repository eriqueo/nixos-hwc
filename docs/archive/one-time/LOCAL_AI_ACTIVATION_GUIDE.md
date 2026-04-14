# LOCAL AI ACTIVATION GUIDE
## Complete Local AI Deployment for nixos-hwc

**Date**: 2025-11-19  
**Status**: Ready for deployment  
**Machines**: hwc-server, hwc-laptop

---

## 🎯 EXECUTIVE SUMMARY

This overhaul transforms your local AI setup from "barely functional" to **production-ready** with:

✅ **4 automated workflows** running on both machines  
✅ **Hardware-optimized models** (3B-7B based on machine capabilities)  
✅ **3 interactive CLI tools** for daily use  
✅ **Charter v6.0 compliant** module architecture  
✅ **Zero broken code** - removed incomplete Fabric API  

---

## 📦 WHAT WAS BUILT

### New Module: `domains/server/ai/local-workflows/`

#### 1. **File Cleanup Agent** 🗂️
- **Auto-organizes** Downloads, inbox folders every 30min (server) / hourly (laptop)
- **Rule-based + AI fallback** categorization
- **Creates folders**: Documents, Pictures, Code, Videos, etc.
- **Manual tool**: `ai-cleanup`

#### 2. **System Journaling** 📝
- **Daily summaries** of system events (server), weekly (laptop)
- **Captures**: systemd errors, container status, NixOS rebuilds
- **Outputs**: `~/Documents/HWC-AI-Journal/YYYY-MM-DD.md`
- **Manual tool**: `ai-journal`

#### 3. **Documentation Generator** 📚
- **Generate docs** for any code file
- **Supports**: Python, Nix, Bash, JS, Rust, Go, etc.
- **Modes**: file docs, function docs, README, Nix module docs
- **Tool**: `ai-doc file script.py`

#### 4. **Interactive Chat** 💬
- **Terminal ChatGPT** with streaming responses
- **Features**: model switching, history, export
- **Tool**: `ai-chat`

---

## 🖥️ MACHINE CONFIGURATIONS

### hwc-server (Quadro P1000, 16GB RAM, 4GB VRAM)

**Models** (load one at a time due to 4GB VRAM):
```
qwen2.5-coder:3b     → 1.9GB  (coding)
phi3.5:3.8b          → 2.3GB  (general)
llama3.2:3b          → 2.0GB  (journaling/chat)
```

**Workflows**:
- Cleanup: Every 30 min (`/mnt/hot/inbox`, `~/Downloads`)
- Journal: Daily 2 AM
- Chat default: `phi3.5:3.8b`

---

### hwc-laptop (32GB RAM, RTX GPU)

**Models** (larger for quality):
```
qwen2.5-coder:7b     → 4.3GB  (premium coding)
llama3.2:3b          → 2.0GB  (battery mode)
mistral:7b-instruct  → 4.1GB  (best reasoning)
```

**Workflows**:
- Cleanup: Hourly (`~/Downloads`)
- Journal: Weekly
- Chat default: `mistral:7b-instruct`

---

## 🚀 ACTIVATION STEPS

### Server Deployment

```bash
# 1. SSH to server
ssh hwc-server

# 2. Pull latest code
cd ~/.nixos
git pull origin claude/local-ai-overhaul-01CVadz9JTpQ4auavQvFWsdd

# 3. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# 4. Monitor model downloads (~6GB)
journalctl -u ollama-pull-models -f

# 5. Verify services
systemctl list-timers | grep ai-
podman ps | grep ollama
```

### Laptop Deployment

```bash
# 1. Pull latest code
cd ~/.nixos
git pull origin claude/local-ai-overhaul-01CVadz9JTpQ4auavQvFWsdd

# 2. Rebuild
sudo nixos-rebuild switch --flake .#hwc-laptop

# 3. Monitor model downloads (~10GB)
journalctl -u ollama-pull-models -f

# 4. Verify
systemctl list-timers | grep ai-
```

---

## 🛠️ USING THE TOOLS

### Chat Interface

```bash
ai-chat
```

**Commands**:
- `/models` - List available models
- `/model qwen2.5-coder:3b` - Switch model
- `/history 20` - Show last 20 messages
- `/export` - Export to Markdown
- `/quit` - Exit

**Example**:
```
You: Write a Python function to validate email addresses
Assistant: *generating streaming response...*
A systemd timer allows you to run tasks on a schedule...
```

---

### Documentation Generator

```bash
# Document a Python file
ai-doc file workspace/utilities/some-script.py

# Document specific function
ai-doc file domains/server/ai/ollama/default.nix -f mkOllamaService

# Generate README for a directory
ai-doc readme workspace/utilities/local-ai/

# Document a Nix module
ai-doc module domains/server/ai/local-workflows/options.nix
```

---

### Manual Workflows

```bash
# Run file cleanup manually
systemctl start ai-file-cleanup.service
journalctl -u ai-file-cleanup -f

# Generate journal entry manually
systemctl start ai-journal.service

# Check journal output
cat ~/Documents/HWC-AI-Journal/$(date +%Y-%m-%d).md
```

---

## 🔍 TROUBLESHOOTING

### Models Not Downloading

```bash
# Check Ollama container
podman logs ollama

# Check pull service
systemctl status ollama-pull-models
journalctl -u ollama-pull-models

# Manually pull a model
podman exec ollama ollama pull qwen2.5-coder:3b
```

---

### Workflows Not Running

```bash
# Check timer status
systemctl list-timers | grep ai-

# Check service status
systemctl status ai-file-cleanup.service
systemctl status ai-journal.service

# View logs
journalctl -u ai-file-cleanup -f
journalctl -u ai-journal -f

# Manually trigger
systemctl start ai-file-cleanup.service
```

---

### Ollama Connection Errors

```bash
# Check Ollama is running
podman ps | grep ollama

# Test connection
curl http://127.0.0.1:11434/api/tags

# Restart Ollama
podman restart ollama
```

---

### Chat Tool Not Finding Models

```bash
# From ai-chat, run:
/models

# If empty, check Ollama:
curl http://127.0.0.1:11434/api/tags

# Pull models manually:
podman exec ollama ollama pull phi3.5:3.8b
```

---

## ⚡ PERFORMANCE EXPECTATIONS

### Server (Quadro P1000)

| Model | Mode | Tokens/sec | Use Case |
|-------|------|------------|----------|
| qwen2.5-coder:3b | GPU | ~40-50 | Code generation |
| phi3.5:3.8b | GPU | ~35-45 | Chat, reasoning |
| llama3.2:3b | GPU | ~45-55 | Fast summaries |

**Note**: With 4GB VRAM, expect one model loaded at a time. Switch costs ~2-5 seconds.

---

### Laptop (32GB RAM, RTX)

| Model | Mode | Tokens/sec | Use Case |
|-------|------|------------|----------|
| qwen2.5-coder:7b | GPU | ~60-80 | Premium coding |
| mistral:7b-instruct | GPU | ~55-75 | Best reasoning |
| llama3.2:3b | GPU | ~100+ | Ultra-fast |

**Battery Mode**: Expect ~30% slower on iGPU or CPU-only.

---

## 📊 FILE LOCATIONS

### Configuration
- Module: `domains/server/ai/local-workflows/`
- Server config: `machines/server/config.nix` (lines 120-167)
- Laptop config: `machines/laptop/config.nix` (lines 222-270)
- Profile: `profiles/ai.nix`

### Data
- Models: `/var/lib/ollama/`
- Journals: `~/Documents/HWC-AI-Journal/`
- Chat history: `~/.local/share/ai-chat/history.db`
- Cleanup rules: `~/.config/ai-cleanup/rules/cleanup-rules.yaml`
- Logs: `/var/log/hwc-ai/`

---

## 🎓 NEXT STEPS

### Immediate (First Week)

1. **Deploy to server** and verify all 3 models download
2. **Test chat CLI** - run `ai-chat` and try `/models`
3. **Monitor first cleanup run** - check logs after 30 min
4. **Wait for first journal** - check output after 2 AM
5. **Generate some docs** - try `ai-doc file` on a script

### Short Term (First Month)

1. **Customize cleanup rules** - add categories for your workflow
2. **Review journal quality** - adjust sources if needed
3. **Deploy to laptop** - test larger models
4. **Try different models** - add tinyllama:1.1b for ultra-fast queries
5. **Build custom prompts** - create templates for common tasks

### Future Enhancements

1. **Add whisper.cpp** for voice transcription
2. **Integrate with MCP** - allow Claude to use local models
3. **Create task-specific agents** - email summarizer, code reviewer
4. **Add embeddings** - RAG over your documentation
5. **Build web UI** - Chainlit or Open WebUI frontend

---

## 🔗 RELATED FILES

- **Commit**: `feat(ai): comprehensive local AI overhaul with practical workflows`
- **Branch**: `claude/local-ai-overhaul-01CVadz9JTpQ4auavQvFWsdd`
- **Modules Created**: 6 files, 1584 insertions
- **Charter Compliant**: Yes (v6.0)

---

## ✅ CHECKLIST

Before deploying, ensure:

- [ ] Latest code pulled from branch
- [ ] Sufficient disk space (server: 10GB, laptop: 15GB)
- [ ] Ollama container will have internet access for downloads
- [ ] User `eric` exists with proper permissions
- [ ] Directories exist: `/mnt/hot/inbox` (server), `~/Downloads` (both)
- [ ] No conflicting AI services running

After deployment:

- [ ] Ollama container running (`podman ps`)
- [ ] Models downloaded (check `/var/lib/ollama/`)
- [ ] Timers active (`systemctl list-timers | grep ai-`)
- [ ] CLI tools work (`ai-chat`, `ai-doc`, `ai-cleanup`)
- [ ] First journal generated (day after deployment)
- [ ] Cleanup ran successfully (30 min after deployment)

---

**End of Guide**

For questions or issues, review:
- Systemd logs: `journalctl -u <service-name> -f`
- Container logs: `podman logs ollama`
- Module source: `domains/server/ai/local-workflows/`
