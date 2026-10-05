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
- JT MCP source code is deployed to `/opt/business/jt-mcp` at runtime (not in workspace)
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-10-05: Structure block catches up to `4f199955` (2026-05-21), which deleted the
  re-introduced dead `heartwood/` tree (`index.nix`, `default.nix`, its README) and the
  orphaned `options.nix` — 293 deletions, nothing left enabling them.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
