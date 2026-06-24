# AI MCP

## Purpose
Model Context Protocol servers for AI tool integration.

## Boundaries
- Manages: MCP server configurations, tool definitions
- Does NOT manage: LLM inference → `ollama/`, UI → `open-webui/`

## Structure
```
mcp/
├── default.nix    # Import wrapper
├── index.nix      # MCP infrastructure (mkMcpService, proxy, filesystem server)
└── heartwood/     # JT MCP Server — unified business system interface
    ├── index.nix  # NixOS module (systemd service, options, validation)
    └── README.md  # Heartwood-specific docs
```

## Notes
- JT MCP source code is deployed to `/opt/business/jt-mcp` at runtime (not in workspace)
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-06-22: Refresh README (Sprint 5 MCP/agent/discovery integration; Sprint 4.1 model validation + health checks; Sprint 3 MCP hardening + reverse proxy; Sprint 1 hwc.ai.* namespace; options.nix orphan cleanup).
