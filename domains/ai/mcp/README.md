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
└── heartwood/     # JT MCP Server — unified business system interface
    ├── index.nix  # NixOS module (systemd service, options, validation)
    └── README.md  # Heartwood-specific docs
```

## Notes
- JT MCP source code is deployed to `/opt/business/jt-mcp` at runtime (not in workspace)
- The old `workspace/projects/jt-mcp/` was removed during the 2026-03-26 workspace restructure

## Changelog
- 2026-06-16: Mechanical sweep — Sprint 3 hardened MCP security + reverse-proxy
  support (`9a54f534`), Sprint 4.1 added model validation + health checks
  (`9453c19e`), Sprint 5 integrated MCP/agent/discovery (`b7862937`),
  Sprint 1 consolidated to `hwc.ai.*` namespace (`f9b7fee5`). Plus repo-wide
  carries: `ai refactor` (`5e27cd37`), Phase 1-3 tech-debt (`15f2d60f`),
  dead-tree purge (`efd7063e`).
- 2026-03-26: jt-mcp decoupled from parent hwc.ai.mcp.enable — now standalone; enabled directly in server config
- 2026-03-25: Added heartwood/ subdomain — JT MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
