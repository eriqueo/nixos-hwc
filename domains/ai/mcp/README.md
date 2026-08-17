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
- 2026-08-17: Structure block corrected — it still listed `heartwood/`, deleted in 2026-05-21 (`4f199955`).
- 2026-05-21: `4f199955` — removed the orphan `mcp/heartwood/` subdir (`index.nix`, `default.nix`, `README.md`; live MCP wiring had moved to `domains/business/mcp/`) and the orphan `mcp/options.nix`, whose options are declared inline in `index.nix` per Law 10. -314 lines across the two.
- 2026-04-14: `254f799c` — xps/remote-main sync merge re-introduced `heartwood/` and expanded `index.nix` (+76); the re-introduction is what `4f199955` above then deleted.
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
