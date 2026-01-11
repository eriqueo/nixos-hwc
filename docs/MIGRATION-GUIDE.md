# AI Domain Refactoring Migration Guide

This document provides the steps to complete the AI domain refactoring after all PRs are merged.

## Overview

The refactoring consists of 5 PRs that must be merged and applied in order:

1. **PR 1**: Skeleton files for `domains/ai`
2. **PR 2**: Copy modules and apply Open WebUI fixes
3. **PR 3**: Migrate server machine configuration
4. **PR 4**: Migrate laptop machine configuration
5. **PR 5**: Add FastAPI agent and integration

## Post-Merge Integration Steps

### After PR 1 and PR 2 are merged

The `domains/ai` structure will exist but won't be used yet. No action needed until PR 3.

### After PR 3 is merged (Server)

1. **Pull the changes on the server**:
   ```bash
   cd ~/.nixos  # or wherever your nixos-hwc repo is
   git pull origin main
   ```

2. **Review the changes**:
   ```bash
   git log --oneline -5
   git diff HEAD~1 machines/server/config.nix
   ```

3. **Rebuild the server** (in a maintenance window):
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-server
   ```

4. **Verify services are running**:
   ```bash
   systemctl status oci-containers-ollama.service
   systemctl status oci-containers-open-webui.service
   podman ps
   ```

5. **Test Ollama**:
   ```bash
   curl http://127.0.0.1:11434/api/tags
   ```

6. **Test Open WebUI**:
   - Access: https://hwc.ocelot-wahoo.ts.net:3443
   - Verify it can connect to Ollama
   - Test a chat interaction

7. **Check logs if issues occur**:
   ```bash
   journalctl -u oci-containers-ollama -f
   journalctl -u oci-containers-open-webui -f
   ```

### After PR 4 is merged (Laptop)

1. **Pull the changes on the laptop**:
   ```bash
   cd ~/.nixos
   git pull origin main
   ```

2. **Rebuild the laptop**:
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

3. **Test ai-chat CLI**:
   ```bash
   ai-chat
   # In the chat, try: /models
   # Try a command: "show me running containers"
   ```

4. **Verify Ollama endpoint**:
   - If using local Ollama: should connect to localhost:11434
   - If using remote: verify it connects to server

### After PR 5 is merged (Agent)

1. **Update domains/ai/default.nix** to import agent:
   ```bash
   cd ~/.nixos
   # Edit domains/ai/default.nix and add ./agent/default.nix to imports
   ```

2. **Enable agent on server** in `machines/server/config.nix`:
   ```nix
   hwc.ai.agent = {
     enable = true;
   };
   ```

3. **Update Open WebUI config** to use agent:
   ```nix
   hwc.ai.open-webui = {
     enable = true;
     extraEnv = {
       HWC_AGENT_URL = "http://127.0.0.1:6020";
     };
   };
   ```

4. **Rebuild server**:
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-server
   ```

5. **Test agent**:
   ```bash
   # Check service
   sudo systemctl status hwc-ai-agent
   
   # Test allowed command
   curl -sS -X POST http://127.0.0.1:6020/run \
     -H "Content-Type: application/json" \
     -d '{"cmd":"podman ps"}'
   
   # Test forbidden command (should fail)
   curl -sS -X POST http://127.0.0.1:6020/run \
     -H "Content-Type: application/json" \
     -d '{"cmd":"rm -rf /"}'
   
   # Check audit log
   sudo tail -f /var/log/hwc-ai/agent-audit.log
   ```

6. **Configure Open WebUI tool** (via web UI):
   - Go to Open WebUI admin panel
   - Navigate to Tools
   - Add new tool:
     - Name: "System Command"
     - Type: "HTTP POST"
     - URL: `http://127.0.0.1:6020/run`
     - Body: `{"cmd": "{{command}}"}`

7. **Test from Open WebUI**:
   - Start a chat
   - Try invoking the system command tool
   - Verify audit logs show the execution

## Rollback Procedures

### If server rebuild fails

```bash
sudo nixos-rebuild switch --rollback
```

### If Open WebUI can't connect to Ollama

1. Check Ollama is running:
   ```bash
   systemctl status oci-containers-ollama.service
   podman ps | grep ollama
   ```

2. Check Open WebUI can reach Ollama:
   ```bash
   podman exec -it open-webui curl http://ollama:11434/api/tags
   ```

3. Check systemd dependencies:
   ```bash
   systemctl show oci-containers-open-webui.service | grep -E "(After|Wants)"
   ```

4. If needed, restart services:
   ```bash
   sudo systemctl restart oci-containers-ollama.service
   sudo systemctl restart oci-containers-open-webui.service
   ```

### If agent fails to start

1. Check logs:
   ```bash
   journalctl -u hwc-ai-agent -f
   ```

2. Check Python dependencies:
   ```bash
   python3 -c "import fastapi, uvicorn, pydantic"
   ```

3. Test agent script manually:
   ```bash
   /nix/store/*/bin/hwc-ai-agent --help
   ```

## Verification Checklist

After all PRs are merged and applied:

- [ ] Server: Ollama container running
- [ ] Server: Open WebUI container running
- [ ] Server: Open WebUI can access Ollama
- [ ] Server: AI agent service running
- [ ] Server: Agent responds to test commands
- [ ] Server: Agent rejects forbidden commands
- [ ] Server: Audit log is being written
- [ ] Laptop: ai-chat CLI works
- [ ] Laptop: Can connect to Ollama (local or remote)
- [ ] Both: systemPrompt is inherited from domain defaults
- [ ] Both: No implementation logic in machine configs

## Cleanup (Optional)

After verifying everything works, you can optionally remove the old `domains/server/ai` directory:

```bash
cd ~/.nixos
git rm -r domains/server/ai/ollama
git rm -r domains/server/ai/open-webui
git rm -r domains/server/ai/local-workflows
git rm -r domains/server/ai/mcp
git commit -m "cleanup: remove old domains/server/ai modules"
git push
```

**Note**: Only do this after confirming the new structure works perfectly!

## Support

If you encounter issues:

1. Check the relevant service logs
2. Verify Nix evaluation: `nix flake check`
3. Test configuration build: `nixos-rebuild build --flake .#hwc-server`
4. Review the PR descriptions for specific test procedures
5. Consult `domains/ai/agent/README.md` for agent-specific troubleshooting

## References

- Original migration plan: `/home/ubuntu/upload/pasted_content.txt`
- Agent documentation: `domains/ai/agent/README.md`
- Charter principles: Project Charter v6.0
