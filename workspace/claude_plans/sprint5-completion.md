# Sprint 5 Completion Plan: Local Workflows API & Open WebUI Integration

**Created**: 2025-12-03
**Status**: Planning
**Goal**: Complete the final two integration tasks for a fully functional AI domain

---

## Current State

### ✅ Completed (Sprints 1-4 + 5.1-5.3)
- Namespace consolidation (Sprint 1)
- Health monitoring system (Sprint 2)
- Security hardening (Sprint 3)
- Model validation, declarative models, disk monitoring (Sprint 4.1-4.2)
- Cloud API infrastructure (Sprint 4.3)
- Model router with local/cloud fallback (Sprint 4.4)
- Agent PATH configuration (Sprint 5.1)
- MCP reverse proxy (Sprint 5.2)
- MCP server discovery endpoint (Sprint 5.3)

### 🎯 Remaining Tasks
- **Sprint 5.4**: Local Workflows API wrapper (FastAPI)
- **Sprint 5.5**: Open WebUI tool integration (declarative config)

---

## Sprint 5.4: Local Workflows API Wrapper

### Objective
Create a FastAPI service that exposes local AI workflows via HTTP API, making them accessible to Open WebUI, external tools, and remote clients.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Local Workflows API (Port 6021)                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  FastAPI Service                                     │   │
│  │  - /chat        → Ollama chat with prompt templates  │   │
│  │  - /cleanup     → Trigger file cleanup workflow      │   │
│  │  - /journal     → Generate journal entry             │   │
│  │  - /autodoc     → Generate documentation             │   │
│  │  - /status      → Workflow status and stats          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ↓
        ┌──────────────────┴──────────────────┐
        │                                     │
        ↓                                     ↓
┌───────────────────┐              ┌──────────────────┐
│  Ollama API       │              │  System Services │
│  (Port 11434)     │              │  - Cleanup timer │
│  - Chat           │              │  - Journal timer │
│  - Model info     │              └──────────────────┘
└───────────────────┘
```

### Implementation Steps

#### 1. Create Module Structure
```
domains/ai/local-workflows/
├── options.nix          # API options (port, enable, auth)
├── default.nix          # Systemd service, security
├── api/
│   ├── server.py        # FastAPI application
│   ├── models.py        # Pydantic models
│   ├── workflows.py     # Workflow execution logic
│   └── prompts.py       # Prompt templates
└── parts/
    └── systemd.nix      # Service config helpers
```

#### 2. API Endpoints Design

**POST /api/workflows/chat**
```json
{
  "message": "Explain this error",
  "context": "optional file content",
  "model": "qwen2.5-coder:3b",
  "system_prompt": "optional override"
}
```
Response: Streaming SSE or JSON response from Ollama

**POST /api/workflows/cleanup**
```json
{
  "directory": "/mnt/hot/inbox",
  "dry_run": false
}
```
Response: List of files analyzed and actions taken

**POST /api/workflows/journal**
```json
{
  "sources": ["systemd-journal", "container-logs"],
  "time_range": "24h"
}
```
Response: Generated journal entry in markdown

**POST /api/workflows/autodoc**
```json
{
  "file_path": "/home/eric/.nixos/domains/ai/router/default.nix",
  "style": "technical|user-friendly"
}
```
Response: Generated documentation

**GET /api/workflows/status**
```json
{
  "workflows": {
    "file_cleanup": {
      "last_run": "2025-12-03T02:30:00Z",
      "next_run": "2025-12-03T03:00:00Z",
      "files_processed": 42,
      "status": "healthy"
    },
    "journaling": {...}
  },
  "models": {
    "qwen2.5-coder:3b": "available",
    "llama3.2:3b": "available"
  }
}
```

#### 3. Security Considerations
- Run as dedicated `ai-workflows` user
- Read-only access except for:
  - `/mnt/hot/inbox` (cleanup)
  - `/home/eric/Documents/HWC-AI-Journal` (journaling)
- MemoryMax: 2G (workflows can be memory-intensive)
- CPUQuota: 200% (allow burst for processing)
- Localhost-only binding by default
- Optional API key authentication

#### 4. Integration Points
- Add to `/discovery` endpoint
- Add Caddy route: `/workflows` → `http://127.0.0.1:6021`
- Update health monitoring
- Add to Sprint verification tests

#### 5. NixOS Configuration
```nix
hwc.ai.local-workflows.api = {
  enable = true;
  port = 6021;
  auth.enable = false;  # Enable for production

  # Workflow-specific settings
  cleanup.allowedDirs = [ "/mnt/hot/inbox" "/home/eric/Downloads" ];
  journal.outputDir = "/home/eric/Documents/HWC-AI-Journal";
  autodoc.allowedDirs = [ "/home/eric/.nixos" "/home/eric/projects" ];
};
```

---

## Sprint 5.5: Open WebUI Tool Integration

### Objective
Enable Open WebUI to use system tools, MCP servers, and local workflows through declarative NixOS configuration, creating a unified AI assistant interface.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Open WebUI (Port 3001)                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Tool Registry (declarative)                         │   │
│  │  ├── System Tools (via Agent)                        │   │
│  │  │   - podman ps, systemctl status, journalctl      │   │
│  │  ├── MCP Tools (via mcp-proxy)                       │   │
│  │  │   - read_file, write_file, list_directory        │   │
│  │  └── Workflow Tools (via Workflows API)              │   │
│  │      - cleanup, journal, autodoc                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ↓                  ↓                  ↓
┌───────────────┐  ┌──────────────┐  ┌──────────────────┐
│  AI Agent     │  │  MCP Proxy   │  │  Workflows API   │
│  (Port 6020)  │  │  (Port 6001) │  │  (Port 6021)     │
└───────────────┘  └──────────────┘  └──────────────────┘
```

### Open WebUI Tool Integration Methods

Open WebUI supports tools via:
1. **OpenAI Function Calling Format** (recommended)
2. **Custom Tool Plugins** (Python-based)
3. **External API Integration**

We'll use **OpenAI Function Calling** for maximum compatibility.

### Implementation Steps

#### 1. Tool Definition Format

Open WebUI expects tools in OpenAI function calling format:

```json
{
  "type": "function",
  "function": {
    "name": "system_status",
    "description": "Check system service status",
    "parameters": {
      "type": "object",
      "properties": {
        "service": {
          "type": "string",
          "description": "Service name (e.g., 'ollama', 'caddy')"
        }
      },
      "required": ["service"]
    }
  }
}
```

#### 2. Create Tool Registry Module

```
domains/ai/open-webui/
├── tools/
│   ├── registry.json       # Generated tool definitions
│   ├── system.nix          # System tool definitions
│   ├── mcp.nix             # MCP tool definitions
│   └── workflows.nix       # Workflow tool definitions
└── parts/
    └── tool-generator.nix  # Nix functions to generate JSON
```

#### 3. Declarative Tool Configuration

```nix
hwc.ai.open-webui.tools = {
  enable = true;

  # System tools (via agent)
  system = {
    enable = true;
    allowedCommands = [
      { name = "container_status"; command = "podman ps"; description = "List running containers"; }
      { name = "service_status"; command = "systemctl status"; description = "Check service status"; }
      { name = "recent_logs"; command = "journalctl -n"; description = "View recent system logs"; }
    ];
  };

  # MCP tools (filesystem access)
  mcp = {
    enable = true;
    server = "http://127.0.0.1:6001";
    capabilities = [ "read_file" "write_file" "list_directory" ];
  };

  # Workflow tools
  workflows = {
    enable = true;
    api = "http://127.0.0.1:6021";
    exposed = [
      { name = "cleanup_downloads"; workflow = "cleanup"; description = "Organize messy directories"; }
      { name = "generate_journal"; workflow = "journal"; description = "Create daily journal entry"; }
      { name = "document_code"; workflow = "autodoc"; description = "Generate code documentation"; }
    ];
  };
};
```

#### 4. Tool Executor Middleware

Create a middleware service that translates Open WebUI function calls to actual API calls:

```python
# domains/ai/open-webui/tools/executor.py

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx

app = FastAPI(title="Open WebUI Tool Executor")

class FunctionCall(BaseModel):
    name: str
    arguments: dict

@app.post("/execute")
async def execute_function(call: FunctionCall):
    """Execute a tool function and return results"""

    if call.name.startswith("system_"):
        # Route to agent
        return await execute_agent_command(call)
    elif call.name.startswith("mcp_"):
        # Route to MCP proxy
        return await execute_mcp_function(call)
    elif call.name.startswith("workflow_"):
        # Route to workflows API
        return await execute_workflow(call)
    else:
        raise HTTPException(404, f"Unknown function: {call.name}")
```

#### 5. Open WebUI Configuration

Open WebUI stores tool configurations in its database or config files. We'll need to:

1. **Generate tool registry JSON** from NixOS config
2. **Mount as volume** into Open WebUI container
3. **Configure environment** to load tools on startup

```nix
# In domains/ai/open-webui/default.nix
environment.systemPackages = [
  (pkgs.writeTextFile {
    name = "openwebui-tools.json";
    text = builtins.toJSON (generateToolRegistry cfg.tools);
    destination = "/share/openwebui/tools.json";
  })
];

# Container mount
virtualisation.oci-containers.containers.open-webui = {
  volumes = [
    "${toolsJson}:/app/backend/tools.json:ro"
  ];
  environment = {
    ENABLE_TOOLS = "true";
    TOOLS_CONFIG = "/app/backend/tools.json";
  };
};
```

#### 6. Tool Categories

**System Tools (via Agent):**
- `system_container_list`: List running containers
- `system_service_status`: Check systemd service status
- `system_recent_logs`: View recent journalctl entries
- `system_disk_usage`: Check disk space

**MCP Tools (via mcp-proxy):**
- `mcp_read_file`: Read file from ~/.nixos
- `mcp_write_file`: Write file to ~/.nixos-mcp-drafts
- `mcp_list_directory`: List directory contents
- `mcp_search_files`: Search for files by name/content

**Workflow Tools (via Workflows API):**
- `workflow_cleanup`: Organize downloads/inbox
- `workflow_journal`: Generate daily journal
- `workflow_autodoc`: Document code files
- `workflow_chat`: Chat with context-aware prompts

#### 7. Security & Permissions

- Tool executor runs as `open-webui-tools` user
- No direct system access - all calls proxied through APIs
- Agent enforces command allowlist
- MCP enforces directory restrictions
- Workflows API enforces allowed paths
- All tools log to `/var/log/hwc-ai/tool-executor.log`

#### 8. Testing Strategy

1. Generate tool registry from config
2. Verify JSON format matches OpenAI function calling spec
3. Test each tool category independently
4. Test from Open WebUI interface
5. Verify security restrictions work
6. Test error handling (invalid commands, timeouts)

---

## Implementation Order

### Phase 1: Local Workflows API (Sprint 5.4)
**Estimated Time**: 2-3 hours
**Priority**: High - Enables workflow automation via HTTP

1. Create module structure in `domains/ai/local-workflows/api/`
2. Implement FastAPI server with basic endpoints
3. Add systemd service configuration
4. Test each endpoint independently
5. Add to discovery endpoint
6. Add Caddy route
7. Document API in README

### Phase 2: Open WebUI Tool Integration (Sprint 5.5)
**Estimated Time**: 2-3 hours
**Priority**: High - Completes unified AI assistant interface

1. Research Open WebUI tool configuration format
2. Create tool definition generator in Nix
3. Implement tool executor middleware
4. Configure Open WebUI container to load tools
5. Test tool execution from UI
6. Add security validations
7. Document tool usage

### Phase 3: Testing & Documentation
**Estimated Time**: 1 hour
**Priority**: Medium

1. Create comprehensive test suite
2. Verify all Sprint 1-5 features working
3. Update CHARTER.md with AI domain patterns
4. Create user guide for AI workflows
5. Document troubleshooting steps

---

## Success Criteria

### Sprint 5.4 Complete When:
- [ ] Workflows API running on port 6021
- [ ] All endpoints responding correctly
- [ ] Chat endpoint streaming from Ollama
- [ ] Cleanup workflow executing successfully
- [ ] Journal generation working
- [ ] Autodoc generating documentation
- [ ] Status endpoint showing accurate info
- [ ] Added to discovery endpoint
- [ ] Caddy route proxying correctly
- [ ] Security restrictions enforced

### Sprint 5.5 Complete When:
- [ ] Tool registry generated from NixOS config
- [ ] Open WebUI loading tools on startup
- [ ] System tools executing via agent
- [ ] MCP tools accessing filesystem
- [ ] Workflow tools triggering APIs
- [ ] Tool executor logging all calls
- [ ] Security restrictions enforced
- [ ] All tools visible in Open WebUI interface
- [ ] Error handling working correctly
- [ ] Documentation complete

### Overall Sprint 5 Complete When:
- [ ] All Sprints 1-5 features verified working
- [ ] Integration tests passing
- [ ] Documentation updated
- [ ] No regressions in previous sprints
- [ ] Commit messages follow conventions
- [ ] Charter compliance maintained

---

## Potential Challenges & Solutions

### Challenge 1: Open WebUI Tool Format
**Issue**: Open WebUI's tool format may differ from documentation
**Solution**: Inspect Open WebUI source code or database schema to determine exact format needed

### Challenge 2: Streaming Responses
**Issue**: Workflows API needs to stream Ollama responses
**Solution**: Use FastAPI StreamingResponse with SSE format

### Challenge 3: Tool Execution Timeout
**Issue**: Some workflows may take longer than default timeout
**Solution**: Configure per-tool timeouts, show progress indicators

### Challenge 4: Container Volume Mounts
**Issue**: Open WebUI container needs access to tool registry
**Solution**: Generate JSON file at build time, mount as read-only volume

### Challenge 5: Error Propagation
**Issue**: Tool errors need to be user-friendly in Open WebUI
**Solution**: Implement error transformation layer that converts technical errors to user-facing messages

---

## Post-Completion Enhancements (Future Work)

These are optional improvements beyond Sprint 5 scope:

1. **Tool Usage Analytics**: Track which tools are used most, success rates
2. **Custom Workflows**: Allow users to define custom workflows via UI
3. **Multi-Model Routing**: Route tool calls to appropriate models automatically
4. **Workflow Chaining**: Allow tools to call other tools
5. **Approval Workflow**: Require user approval for destructive operations
6. **Tool Marketplace**: Share tool definitions with community
7. **Voice Integration**: Add voice input/output for hands-free operation
8. **Mobile UI**: Create mobile-friendly interface for common tools

---

## Files to Create/Modify

### New Files:
- `domains/ai/local-workflows/api/server.py`
- `domains/ai/local-workflows/api/models.py`
- `domains/ai/local-workflows/api/workflows.py`
- `domains/ai/local-workflows/api/prompts.py`
- `domains/ai/local-workflows/options.nix` (API section)
- `domains/ai/open-webui/tools/executor.py`
- `domains/ai/open-webui/tools/registry.nix`
- `domains/ai/open-webui/tools/system.nix`
- `domains/ai/open-webui/tools/mcp.nix`
- `domains/ai/open-webui/tools/workflows.nix`

### Modified Files:
- `domains/ai/local-workflows/default.nix` (add API service)
- `domains/ai/open-webui/default.nix` (add tool integration)
- `domains/ai/open-webui/options.nix` (add tools.* options)
- `domains/ai/agent/hwc-ai-agent.py` (update discovery endpoint)
- `domains/server/routes.nix` (add /workflows route)
- `machines/server/config.nix` (enable new features)

---

## Verification Commands

```bash
# Verify Workflows API
curl http://127.0.0.1:6021/api/workflows/status
curl -X POST http://127.0.0.1:6021/api/workflows/chat \
  -d '{"message":"Hello","model":"qwen2.5-coder:3b"}'

# Verify Tool Registry
cat /nix/store/*-openwebui-tools.json | jq

# Verify Open WebUI Tools
# (In Open WebUI UI, check tools menu)

# Verify Discovery Endpoint (updated)
curl http://127.0.0.1:6020/discovery | jq .ai_services.local_workflows.api

# Full System Check
systemctl status hwc-ai-workflows-api.service
systemctl status hwc-ai-agent.service
systemctl status mcp-proxy.service
systemctl status open-webui.service
```

---

## Timeline Estimate

- **Sprint 5.4**: 3-4 hours (Workflows API implementation and testing)
- **Sprint 5.5**: 3-4 hours (Tool integration and testing)
- **Testing & Documentation**: 1-2 hours
- **Total**: 7-10 hours

**Target Completion**: 1-2 work sessions

---

## Notes

- This completes the original AI Domain Improvement Plan
- All infrastructure (Ollama, health, router, cloud, MCP, agent) is operational
- These final tasks focus on accessibility and user experience
- After completion, the system will have a fully integrated AI assistant with system access, file management, and workflow automation
- Charter v7.0 compliance maintained throughout

---

**Plan Status**: Ready for Implementation
**Next Step**: Begin Sprint 5.4 - Local Workflows API wrapper implementation
