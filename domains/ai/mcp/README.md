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
- The `heartwood/` (JT MCP) subdomain was removed — the Heartwood MCP now lives in
  `domains/business/mcp/`.

## Changelog
- 2026-07-06: Removed the re-introduced `heartwood/` dead tree (index.nix + default.nix +
  README) — Heartwood MCP had already moved to `domains/business/mcp/`. Structure block
  corrected to drop the stale subdomain.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
