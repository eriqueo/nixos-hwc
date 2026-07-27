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
- The heartwood (JT MCP) server moved out to `domains/business/mcp/`

## Changelog
- 2026-05-21: Removed `heartwood/` subtree (heartwood MCP relocated to `domains/business/mcp/`) and the orphan `options.nix` — options now declared inline in `index.nix` (4f199955). Structure/Notes updated to match.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
