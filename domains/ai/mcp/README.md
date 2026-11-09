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
└── README.md
```

## Notes
- The heartwood/JT MCP module no longer lives here (removed 2026-05-21).
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-05-21: Deleted the `heartwood/` subdirectory (`default.nix`, `index.nix`,
  `README.md`) in 4f199955. It was re-introduced by merge 254f799c and was not
  imported. The commit message says the heartwood MCP moved to
  `domains/business/mcp/`; that directory does not exist at this refresh.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
