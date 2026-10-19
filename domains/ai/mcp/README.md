# AI MCP

## Purpose
Model Context Protocol servers for AI tool integration.

## Boundaries
- Manages: MCP server configurations, tool definitions
- Does NOT manage: the unified MCP gateway → `domains/system/mcp/`, the business
  (heartwood/JT) MCP → `domains/business/mcp/`

## Structure
```
mcp/
├── default.nix    # Import wrapper
├── index.nix      # MCP infrastructure (mkMcpService, proxy, filesystem server)
└── README.md      # This file
```

## Notes
- The heartwood/JT MCP module no longer lives here — it moved to `domains/business/mcp/`.
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure.

## Changelog
- 2026-05-21: `heartwood/` deleted from this directory (the heartwood MCP module had
  already moved to `domains/business/mcp/`), along with the orphan `mcp/options.nix`
  split file — options are declared inline in `index.nix` now. Structure block above
  corrected; it had still listed `heartwood/`. Same commit removed the dead
  `ai/anything-llm/`, `ai/open-webui/` and `ai/router/` trees, so the old
  "UI → `open-webui/`" boundary pointer is gone too (`4f199955`).
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
