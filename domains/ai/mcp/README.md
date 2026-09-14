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
└── index.nix      # MCP infrastructure (mkMcpService, proxy, filesystem server)
```

## Notes
- The heartwood/JT MCP module is gone from here; JT is now a stdio backend of the
  unified gateway in `domains/system/mcp/` (`parts/jt.nix`)
- JT MCP source code is deployed to `/opt/business/jt-mcp` at runtime (not in workspace)
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-05-21: Removed `heartwood/` (module + README) in the dead-tree and orphan
  `options.nix` sweep (`4f199955`); JT MCP is served from `domains/system/mcp/` now
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
