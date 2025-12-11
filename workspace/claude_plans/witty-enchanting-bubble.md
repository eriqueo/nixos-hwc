# AI Domain Improvement Plan

## Executive Summary

Comprehensive improvement plan for the nixos-hwc AI domain focusing on reliability, architecture, and integration. Prioritizes performance and Charter compliance while maintaining local-first philosophy with hybrid cloud support.

## Current State Analysis

### What's Working
- ✅ Ollama running with GPU acceleration (Quadro P1000 CUDA 6.1)
- ✅ Open WebUI operational on port 3001 (fixed port conflict)
- ✅ 5 models loaded and available
- ✅ Local workflows infrastructure (file-cleanup, journaling, auto-doc, chat-cli)
- ✅ MCP server with filesystem access (partially complete)
- ✅ Transcript API integration with CouchDB

### Critical Issues

#### 1. Namespace Confusion (Architecture)
**Problem**: Mixed `hwc.ai.*` and `hwc.server.ai.*` namespaces causing confusion
- `domains/ai/options.nix` defines both `hwc.ai.enable` AND `hwc.server.ai.ollama.*`
- `profiles/ai.nix` uses `hwc.ai.ollama`
- `machines/server/config.nix` uses `hwc.ai.ollama`
- Violates Charter principle of clear namespace mapping

**Impact**: Configuration ambiguity, potential conflicts, unclear ownership

#### 2. Missing Health Checks & Monitoring (Reliability)
**Problem**: No systematic health monitoring for AI services
- Ollama has no health endpoint checks
- Open WebUI has no liveness probes
- No Prometheus exporters for AI metrics
- Transcript API has `/health` but not monitored

**Impact**: Silent failures, no alerting, difficult troubleshooting

#### 3. MCP Security TODOs (Reliability)
**Problem**: MCP services have relaxed security with `# TODO: Tighten security once working`
- `ProtectSystem = "true"` instead of "strict"
- Broad filesystem access for npx
- No resource limits

**Impact**: Security posture weaker than it should be

#### 4. Incomplete Integration (Integration)
**Problem**: Open WebUI and local workflows not fully integrated
- Agent (hwc-ai-agent.py) exists but not integrated
- No tool registration documented
- MCP reverse proxy disabled
- Local workflows don't expose APIs

**Impact**: Limited functionality, manual configuration required

#### 5. No Model Management (Missing Feature)
**Problem**: Models downloaded at startup but no lifecycle management
- No model validation
- No model update mechanism
- No disk space monitoring
- Hardcoded model list

**Impact**: Stale models, disk space issues, manual maintenance

## Recommended Solution

### Phase 1: Architecture & Namespace Cleanup (Priority: High)

#### 1.1 Consolidate to `hwc.ai.*` Namespace
**Rationale**: Single, clear namespace following Charter principles

**Changes**:
1. **domains/ai/options.nix** - Remove `hwc.server.ai.*`, keep only `hwc.ai.*`
2. **domains/server/ai/** - Delete entire directory (move implementations to domains/ai/)
3. **Update all imports** - Point to domains/ai/ consistently
4. **Namespace structure**:
   ```
   hwc.ai.enable          # Top-level toggle
   hwc.ai.ollama.*        # Ollama service
   hwc.ai.open-webui.*    # Open WebUI
   hwc.ai.local-workflows.* # Local workflows
   hwc.ai.mcp.*           # MCP servers
   hwc.ai.agent.*         # Agent (future)
   ```

**Files to modify**:
- `domains/ai/options.nix` - Consolidate all options
- `domains/ai/default.nix` - Remove server/ai references
- `profiles/ai.nix` - Update to use hwc.ai.*
- `machines/server/config.nix` - Update configuration
- Delete `domains/server/ai/` entirely

**Validation**: Charter linter passes, no namespace conflicts

#### 1.2 Proper Module Structure
**Changes**:
- Ensure all modules have OPTIONS, IMPLEMENTATION, VALIDATION sections
- Add proper dependency assertions
- Follow Frigate pattern for Charter v7.0 compliance

### Phase 2: Health Checks & Basic Monitoring (Priority: High)

#### 2.1 Service Health Endpoints
**Implementation**:

**Ollama Health Check**:
```nix
systemd.services.ollama-health = {
  description = "Ollama health check";
  after = [ "oci-containers-ollama.service" ];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = pkgs.writeShellScript "ollama-health" ''
      ${pkgs.curl}/bin/curl -f http://localhost:11434/api/tags > /dev/null 2>&1
    '';
  };
};

systemd.timers.ollama-health = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnBootSec = "2min";
    OnUnitActiveSec = "5min";
  };
};
```

**Open WebUI Health Check**:
```nix
# Add healthcheck to container extraOptions
extraOptions = [
  "--health-cmd=wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1"
  "--health-interval=30s"
  "--health-timeout=10s"
  "--health-retries=3"
];
```

**Files to modify**:
- `domains/ai/ollama/default.nix` - Add health timer
- `domains/ai/open-webui/default.nix` - Add container health check
- `domains/ai/options.nix` - Add `healthCheck.enable` options

#### 2.2 Transcript API Monitoring Integration
**Implementation**:
Add Prometheus scrape config for transcript API `/health` endpoint

**Files to modify**:
- `profiles/monitoring.nix` - Add scrape config when transcript-api enabled

#### 2.3 Simple Dashboards
**Implementation**:
Create basic Grafana dashboard JSON for AI services (status, model availability)

**Files to add**:
- `domains/ai/monitoring/dashboards/ai-services.json`

### Phase 3: MCP Security Hardening (Priority: Medium)

#### 3.1 Tighten MCP Service Security
**Changes**:
1. Implement proper `ReadOnlyPaths`/`ReadWritePaths` for npx
2. Add `MemoryMax`, `CPUQuota` resource limits
3. Re-enable `PrivateNetwork` where possible
4. Document security exceptions with justifications

**Files to modify**:
- `domains/ai/mcp/default.nix` - Remove TODOs, add hardening

#### 3.2 MCP Reverse Proxy
**Changes**:
1. Add `hwc.ai.mcp.reverseProxy` options properly scoped
2. Integrate with `domains/server/routes.nix` when on server
3. Add authentication layer (basic auth or API key)

**Files to modify**:
- `domains/ai/mcp/options.nix` - Add reverse proxy options
- `domains/ai/mcp/default.nix` - Implement reverse proxy config
- `domains/server/routes.nix` - Add MCP route when enabled

### Phase 4: Integration Improvements (Priority: Medium)

#### 4.1 Open WebUI Tool Integration
**Implementation**:
1. Document tool registration process in README
2. Create example tool definitions for common operations
3. Add `hwc.ai.open-webui.tools` option for declarative tool config

**Files to modify**:
- `domains/ai/open-webui/options.nix` - Add `tools` option
- `domains/ai/open-webui/default.nix` - Generate tool config
- `domains/ai/open-webui/README.md` - Document tool usage

#### 4.2 Local Workflows API Exposure
**Implementation**:
Create lightweight FastAPI wrapper for local workflows (chat-cli, file-cleanup)

**Files to add**:
- `domains/ai/local-workflows/parts/api-server.nix`
- `domains/ai/local-workflows/parts/workflows-api.py`

**Rationale**: Makes local workflows accessible via HTTP for integration

#### 4.3 MCP Server Discovery
**Implementation**:
Add service discovery mechanism for MCP servers

**Files to modify**:
- `domains/ai/mcp/default.nix` - Add discovery endpoint
- `domains/ai/mcp/parts/discovery.nix` - Implement JSON endpoint listing available servers

### Phase 5: Model Management (Priority: Low)

#### 5.1 Model Validation & Health
**Implementation**:
1. Check model integrity after download
2. Test model inference before declaring success
3. Add `ollama-model-health` timer

**Files to modify**:
- `domains/ai/ollama/parts/pull-script.nix` - Add validation
- `domains/ai/ollama/default.nix` - Add health timer

#### 5.2 Declarative Model Configuration
**Implementation**:
```nix
hwc.ai.ollama.models = [
  { name = "llama3.2:3b"; autoUpdate = false; }
  { name = "phi3.5:3.8b"; autoUpdate = true; }
];
```

**Files to modify**:
- `domains/ai/ollama/options.nix` - Change models to attrset
- `domains/ai/ollama/parts/pull-script.nix` - Handle model metadata

#### 5.3 Disk Space Monitoring
**Implementation**:
Add systemd timer to check `/var/lib/ollama` disk usage and warn at 80%

**Files to add**:
- `domains/ai/ollama/parts/disk-monitor.nix`

### Phase 6: Hybrid Cloud Support (Priority: Low)

#### 6.1 OpenAI/Anthropic API Configuration
**Implementation**:
```nix
hwc.ai.cloud = {
  openai = {
    enable = false;
    apiKeyFile = "/run/agenix/openai-api-key";
  };
  anthropic = {
    enable = false;
    apiKeyFile = "/run/agenix/anthropic-api-key";
  };
};
```

**Files to add**:
- `domains/ai/cloud/options.nix`
- `domains/ai/cloud/default.nix`

**Rationale**: Optional cloud fallback for demanding tasks, disabled by default

#### 6.2 Model Router
**Implementation**:
Simple FastAPI service that routes requests to local or cloud based on rules

**Files to add**:
- `domains/ai/router/default.nix`
- `domains/ai/router/model-router.py`

**Rationale**: Transparent fallback without changing client configuration

## Implementation Order

### Sprint 1: Architecture Foundation (Week 1)
- [ ] Namespace consolidation (Phase 1.1)
- [ ] Module structure cleanup (Phase 1.2)
- [ ] Charter lint validation
- [ ] Update documentation

### Sprint 2: Reliability (Week 2)
- [ ] Ollama health checks (Phase 2.1)
- [ ] Open WebUI health checks (Phase 2.1)
- [ ] Transcript API monitoring (Phase 2.2)
- [ ] MCP security hardening (Phase 3.1)

### Sprint 3: Integration (Week 3)
- [ ] Open WebUI tool integration (Phase 4.1)
- [ ] Local workflows API (Phase 4.2)
- [ ] MCP reverse proxy (Phase 3.2)
- [ ] MCP discovery (Phase 4.3)

### Sprint 4: Management & Cloud (Week 4)
- [ ] Model validation (Phase 5.1)
- [ ] Declarative models (Phase 5.2)
- [ ] Disk monitoring (Phase 5.3)
- [ ] Cloud API configuration (Phase 6.1)
- [ ] Model router (Phase 6.2)

## Success Criteria

### Reliability
- ✅ All AI services have health checks running every 5 minutes
- ✅ Systemd failures trigger proper restarts
- ✅ Service dependencies properly declared
- ✅ No services fail silently

### Architecture
- ✅ Single namespace (`hwc.ai.*`) throughout codebase
- ✅ Charter linter passes with zero violations
- ✅ All modules follow OPTIONS/IMPLEMENTATION/VALIDATION pattern
- ✅ Clear dependency chains with assertions

### Integration
- ✅ Open WebUI can execute local workflows via tools
- ✅ MCP servers accessible via reverse proxy
- ✅ Local workflows exposed via API
- ✅ Documentation complete for all integrations

### Monitoring
- ✅ Basic Grafana dashboard shows AI service status
- ✅ Prometheus scrapes health endpoints
- ✅ Failed health checks visible in logs
- ✅ Model availability tracked

## Risk Mitigation

### Breaking Changes
**Risk**: Namespace change breaks existing machine configs
**Mitigation**: Provide migration guide, add legacy compat layer temporarily

### Service Disruption
**Risk**: Changes cause AI services to fail
**Mitigation**: Test in staging, gradual rollout, keep rollback plan

### Security Regressions
**Risk**: MCP changes introduce vulnerabilities
**Mitigation**: Security audit after changes, document all exceptions

## Files to Modify

### High Priority
1. `domains/ai/options.nix` - Consolidate namespace
2. `domains/ai/default.nix` - Update imports
3. `domains/ai/ollama/default.nix` - Add health checks
4. `domains/ai/open-webui/default.nix` - Add health checks
5. `domains/ai/mcp/default.nix` - Security hardening
6. `profiles/ai.nix` - Update to new namespace
7. `machines/server/config.nix` - Update AI configuration

### Medium Priority
8. `domains/ai/mcp/options.nix` - Add reverse proxy
9. `domains/ai/open-webui/options.nix` - Add tools option
10. `domains/server/routes.nix` - Add MCP route
11. `profiles/monitoring.nix` - Add AI scrape configs

### New Files
12. `domains/ai/monitoring/dashboards/ai-services.json`
13. `domains/ai/local-workflows/parts/api-server.nix`
14. `domains/ai/local-workflows/parts/workflows-api.py`
15. `domains/ai/mcp/parts/discovery.nix`
16. `domains/ai/ollama/parts/disk-monitor.nix`

### Files to Delete
- `domains/server/ai/` (entire directory)

## Notes

- Agent (hwc-ai-agent.py) deferred to Phase 7 per user preference
- Focus on local-first with optional cloud fallback
- Keep monitoring lightweight (basic health checks, no full observability stack)
- Ensure all changes are Charter v7.0 compliant
- Test each phase before moving to next
