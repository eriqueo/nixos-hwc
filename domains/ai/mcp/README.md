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
└── README.md      # This file
```

## Changelog
- 2026-05-21: `heartwood/` deleted (`4f199955`, "delete re-introduced dead trees +
  options.nix orphans") — the JT MCP server module, its `default.nix` wrapper and
  its README, 220 lines in all. The tree had been re-introduced by the `254f799c`
  xps/remote-main merge. Structure block and the jt-mcp runtime notes updated to match.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
