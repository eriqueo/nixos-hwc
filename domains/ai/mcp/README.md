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
│                  #   — options are declared inline here, not in a split options.nix
└── README.md      # This file
```

## Notes
- JT MCP source code is deployed to `/opt/business/jt-mcp` at runtime (not in workspace)
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-05-21: Deleted `heartwood/` (`index.nix`, `default.nix`, its README) and this
  directory's `options.nix` — 293 lines, no behavior change. The heartwood MCP module moved
  to `domains/business/mcp/`; `options.nix` was a legacy split file whose options are now
  declared inline in `index.nix`. `ai/index.nix` never imported either path, and the commit
  recorded unchanged toplevel/activation derivation hashes on all four configurations.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
