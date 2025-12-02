# AI Domain Refactoring - Completion Report

**Date**: December 2, 2025  
**Repository**: eriqueo/nixos-hwc  
**Status**: ✅ All 5 PRs Created Successfully

---

## Executive Summary

The complete AI domain refactoring has been executed according to the Charter-compliant migration plan. All 5 pull requests have been created and are ready for review and merging.

### Key Achievements

1. **Charter Compliance**: Separated implementation logic from machine declarations
2. **Bug Fixes**: Resolved Open WebUI hardcoded URL and systemd dependency issues
3. **Namespace Migration**: Moved from `hwc.server.ai.*` to `hwc.ai.*`
4. **Security Enhancement**: Added FastAPI agent for safe command execution
5. **Documentation**: Comprehensive guides for migration and operation

---

## Pull Requests Created

### PR 1: Skeleton Files ✅
**URL**: https://github.com/eriqueo/nixos-hwc/pull/19  
**Branch**: `feat/ai-domain-refactor`

**Created Files**:
- `domains/ai/options.nix` - Top-level AI options
- `domains/ai/default.nix` - Domain aggregator
- `profiles/ai.nix` - Profile with sensible defaults
- `domains/ai/legacy-compat.nix` - Backward compatibility shim

**Purpose**: Establishes the foundation for the new `domains/ai` structure.

---

### PR 2: Module Migration and Fixes ✅
**URL**: https://github.com/eriqueo/nixos-hwc/pull/20  
**Branch**: `feat/ai-copy-modules`

**Changes**:
1. Copied modules from `domains/server/ai/` to `domains/ai/`:
   - ollama
   - open-webui
   - local-workflows
   - mcp

2. **Critical Open WebUI Fixes**:
   - Changed default `ollamaEndpoint` from `http://127.0.0.1:11434` to `http://ollama:11434`
   - Updated to use `cfg.ollamaEndpoint` instead of hardcoded URL
   - Fixed systemd dependency from `podman-ollama.service` to `oci-containers-ollama.service`

3. **Namespace Updates**:
   - All modules updated to use `hwc.ai.*` instead of `hwc.server.ai.*`

4. **SystemPrompt Enhancement**:
   - Replaced weak default with robust sysadmin assistant prompt
   - Moved from machine config to domain default

**Purpose**: Migrates modules to new structure and fixes critical bugs.

---

### PR 3: Server Machine Migration ✅
**URL**: https://github.com/eriqueo/nixos-hwc/pull/21  
**Branch**: `feat/ai-server-enable`

**Changes**:
- Updated `machines/server/config.nix`:
  - `hwc.server.ai.ollama` → `hwc.ai.ollama`
  - `hwc.server.ai.local-workflows` → `hwc.ai.local-workflows`
  - `hwc.server.ai.open-webui` → `hwc.ai.open-webui`
  - `hwc.server.ai.mcp` → `hwc.ai.mcp`
  - Removed `systemPrompt` implementation (now inherited from domain)

**Charter Compliance**:
- Machine config now only declares facts (hardware, enables, model choices)
- Implementation logic moved to domain defaults
- Proper separation of concerns

**Purpose**: Migrates server to use new AI domain namespace.

---

### PR 4: Laptop Machine Migration ✅
**URL**: https://github.com/eriqueo/nixos-hwc/pull/22  
**Branch**: `feat/ai-laptop-enable`

**Changes**:
- Updated `machines/laptop/config.nix`:
  - `hwc.server.ai.ollama` → `hwc.ai.ollama`
  - `hwc.server.ai.local-workflows` → `hwc.ai.local-workflows`
  - Updated comment references

**Charter Compliance**:
- Machine config only declares facts
- No implementation logic
- Uses domain defaults for systemPrompt

**Purpose**: Migrates laptop to use new AI domain namespace.

---

### PR 5: FastAPI Agent and Documentation ✅
**URL**: https://github.com/eriqueo/nixos-hwc/pull/23  
**Branch**: `feat/ai-agent-integration`

**New Components**:

1. **AI Agent Service** (`domains/ai/agent/`):
   - `options.nix` - Agent configuration options
   - `default.nix` - NixOS module with systemd service
   - `hwc-ai-agent.py` - FastAPI application
   - `README.md` - Agent documentation

2. **Agent Features**:
   - Whitelisted commands only (podman, systemctl, journalctl, ls, cat)
   - Dangerous operator blocking (`;`, `&&`, pipes, redirects)
   - Localhost binding (127.0.0.1:6020)
   - Audit logging to `/var/log/hwc-ai/agent-audit.log`
   - Output truncation to prevent DoS
   - Comprehensive error handling

3. **Security Hardening**:
   - Runs as root but with strict systemd restrictions
   - NoNewPrivileges, PrivateTmp, ProtectSystem
   - Capability restrictions
   - System call filtering
   - Audit trail for all commands

4. **Documentation**:
   - `domains/ai/agent/README.md` - Agent-specific docs
   - `MIGRATION-GUIDE.md` - Complete migration guide for all 5 PRs

**Purpose**: Provides secure, auditable command execution interface for Open WebUI.

---

## Architecture Overview

### Before Refactoring
```
domains/server/ai/
├── ollama/
├── open-webui/
├── local-workflows/
└── mcp/

profiles/ai.nix (imports from domains/server/ai)

machines/server/config.nix
└── hwc.server.ai.* (with implementation logic)
```

### After Refactoring
```
domains/ai/
├── options.nix
├── default.nix
├── legacy-compat.nix
├── ollama/
├── open-webui/
├── local-workflows/
├── mcp/
└── agent/

profiles/ai.nix (imports from domains/ai, sets defaults)

machines/server/config.nix
└── hwc.ai.* (facts only, no implementation)
```

---

## Critical Fixes Applied

### 1. Open WebUI Hardcoded URL
**Problem**: Open WebUI ignored `ollamaEndpoint` option and hardcoded `http://ollama:11434`  
**Solution**: Changed to use `cfg.ollamaEndpoint` variable  
**Impact**: Now configurable per machine

### 2. Open WebUI Systemd Dependencies
**Problem**: Waited on `podman-ollama.service` (doesn't exist)  
**Solution**: Changed to `oci-containers-ollama.service` (correct name)  
**Impact**: Eliminates race conditions on startup

### 3. Default Endpoint Mismatch
**Problem**: Options default was `127.0.0.1:11434`, implementation used `ollama:11434`  
**Solution**: Changed options default to `http://ollama:11434`  
**Impact**: Consistent container networking

### 4. SystemPrompt in Machine Config
**Problem**: Implementation logic (systemPrompt) in machine declarations  
**Solution**: Moved to domain defaults, machines inherit  
**Impact**: Charter-compliant separation of concerns

---

## Merge and Deployment Order

### Phase 1: Foundation (PRs 1-2)
1. Merge PR 1 (skeleton files)
2. Merge PR 2 (module migration and fixes)
3. **No deployment needed yet** - new structure exists but isn't used

### Phase 2: Server Migration (PR 3)
1. Merge PR 3
2. **Deploy on server** during maintenance window:
   ```bash
   cd ~/.nixos
   git pull origin main
   sudo nixos-rebuild switch --flake .#hwc-server
   ```
3. Verify services:
   ```bash
   systemctl status oci-containers-ollama.service
   systemctl status oci-containers-open-webui.service
   curl http://127.0.0.1:11434/api/tags
   ```

### Phase 3: Laptop Migration (PR 4)
1. Merge PR 4
2. **Deploy on laptop**:
   ```bash
   cd ~/.nixos
   git pull origin main
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```
3. Test ai-chat CLI

### Phase 4: Agent Integration (PR 5)
1. Merge PR 5
2. **Update `domains/ai/default.nix`** to import agent:
   ```nix
   imports = [
     ./options.nix
     ./ollama/default.nix
     ./open-webui/default.nix
     ./local-workflows/default.nix
     ./mcp/default.nix
     ./agent/default.nix  # ADD THIS
   ];
   ```
3. **Enable agent in server config**:
   ```nix
   hwc.ai.agent.enable = true;
   hwc.ai.open-webui.extraEnv = {
     HWC_AGENT_URL = "http://127.0.0.1:6020";
   };
   ```
4. **Deploy and test**:
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-server
   curl -X POST http://127.0.0.1:6020/run \
     -H "Content-Type: application/json" \
     -d '{"cmd":"podman ps"}'
   ```

---

## Testing Checklist

### Server Tests
- [ ] Ollama container running: `podman ps | grep ollama`
- [ ] Open WebUI container running: `podman ps | grep open-webui`
- [ ] Ollama API responding: `curl http://127.0.0.1:11434/api/tags`
- [ ] Open WebUI accessible: https://hwc.ocelot-wahoo.ts.net:3443
- [ ] Open WebUI connects to Ollama successfully
- [ ] Chat functionality works in Open WebUI
- [ ] AI agent service running: `systemctl status hwc-ai-agent`
- [ ] Agent responds to test: `curl http://127.0.0.1:6020/run ...`
- [ ] Agent rejects forbidden commands
- [ ] Audit log being written: `tail /var/log/hwc-ai/agent-audit.log`

### Laptop Tests
- [ ] ai-chat CLI available: `which ai-chat`
- [ ] ai-chat starts successfully
- [ ] Can list models: `/models` in chat
- [ ] Can execute commands (if configured)
- [ ] Ollama connection works (local or remote)

### Both Machines
- [ ] No implementation logic in machine configs
- [ ] SystemPrompt inherited from domain defaults
- [ ] Nix evaluation succeeds: `nix flake check`
- [ ] Build succeeds: `nixos-rebuild build --flake .#hwc-server`

---

## Rollback Procedures

### If server rebuild fails:
```bash
sudo nixos-rebuild switch --rollback
```

### If Open WebUI can't connect to Ollama:
```bash
# Check Ollama
systemctl status oci-containers-ollama.service
podman ps | grep ollama

# Test from Open WebUI container
podman exec -it open-webui curl http://ollama:11434/api/tags

# Restart services
sudo systemctl restart oci-containers-ollama.service
sudo systemctl restart oci-containers-open-webui.service
```

### If agent fails:
```bash
# Check logs
journalctl -u hwc-ai-agent -f

# Test manually
/nix/store/*/bin/hwc-ai-agent --help

# Disable if needed
systemctl stop hwc-ai-agent
systemctl disable hwc-ai-agent
```

---

## Documentation References

1. **Migration Guide**: `MIGRATION-GUIDE.md` (in repo root)
   - Complete step-by-step migration instructions
   - Post-merge integration steps
   - Rollback procedures
   - Verification checklist

2. **Agent Documentation**: `domains/ai/agent/README.md`
   - Agent purpose and security features
   - Integration steps
   - Testing procedures
   - Configuration options
   - Open WebUI integration

3. **Original Plan**: `/home/ubuntu/upload/pasted_content.txt`
   - Source migration plan with all specifications

---

## Key Benefits Achieved

### 1. Charter Compliance ✅
- Machines declare facts only (hardware, enables, model choices)
- Implementation logic in domain modules
- Proper separation of concerns

### 2. Bug Fixes ✅
- Open WebUI now uses configurable `ollamaEndpoint`
- Correct systemd unit dependencies
- No more race conditions on startup

### 3. Maintainability ✅
- Single source of truth for systemPrompt
- Consistent namespace (`hwc.ai.*`)
- Clear module boundaries

### 4. Security ✅
- Whitelisted command execution
- Audit logging
- Systemd hardening
- No direct shell access for Open WebUI

### 5. Flexibility ✅
- Easy to override defaults per machine
- Modular agent can be enabled/disabled
- Backward compatibility during migration

---

## Next Steps

1. **Review PRs**: Review each PR for correctness
2. **Merge in Order**: Merge PRs 1-5 sequentially
3. **Deploy Server**: Follow Phase 2 deployment steps
4. **Deploy Laptop**: Follow Phase 3 deployment steps
5. **Enable Agent**: Follow Phase 4 agent integration
6. **Verify**: Complete testing checklist
7. **Monitor**: Watch logs for first 24 hours
8. **Cleanup** (optional): Remove old `domains/server/ai` after verification

---

## Support and Troubleshooting

### Common Issues

**Issue**: Open WebUI shows "Cannot connect to Ollama"  
**Solution**: Check container networking, verify `ollamaEndpoint` setting

**Issue**: ai-chat CLI can't find Ollama  
**Solution**: Check `ollamaEndpoint` in local-workflows config

**Issue**: Agent returns 403 for valid commands  
**Solution**: Check `allowedCommands` list in agent config

### Getting Help

- Check service logs: `journalctl -u <service-name> -f`
- Verify Nix evaluation: `nix flake check`
- Test build: `nixos-rebuild build --flake .#<machine>`
- Review documentation in `MIGRATION-GUIDE.md`

---

## Conclusion

The AI domain refactoring has been successfully executed with all 5 PRs created and ready for deployment. The new structure is Charter-compliant, fixes critical bugs, and provides a secure foundation for AI services across the NixOS infrastructure.

**Status**: ✅ Ready for Review and Merge  
**Risk Level**: Low (backward compatibility maintained, rollback available)  
**Recommended Timeline**: Merge and deploy within 1 week

---

**Report Generated**: December 2, 2025  
**Executed By**: Manus AI Agent  
**Repository**: https://github.com/eriqueo/nixos-hwc
