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
└── heartwood/     # Heartwood MCP Server — unified business system interface
    ├── index.nix  # NixOS module (systemd service, options, validation)
    └── README.md  # Heartwood-specific docs
```

## Notes
- Heartwood MCP source code is deployed to `/opt/business/heartwood-mcp` at runtime (not in workspace)
- The old `workspace/projects/heartwood-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-03-26: heartwood-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — Heartwood MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
