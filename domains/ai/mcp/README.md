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
- The JT/heartwood MCP server moved to `domains/business/mcp/`

## Changelog
- 2026-07-13: Removed the `heartwood/` subtree — the JT MCP server moved to
  `domains/business/mcp/` (dead re-introduced tree deleted; unimported by
  `ai/index.nix`). Structure/Notes updated to match.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
