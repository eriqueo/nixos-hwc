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
└── heartwood/     # Heartwood MCP Server — unified business system interface
    ├── index.nix  # NixOS module (systemd service, options, validation)
    └── README.md  # Heartwood-specific docs
```

## Changelog
- 2026-03-25: Added heartwood/ subdomain — Heartwood MCP Server (Phase 1: 63 JT tools)
- 2026-02-28: Added README for Charter Law 12 compliance
