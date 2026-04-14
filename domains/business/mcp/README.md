# JT MCP Server

## Purpose
NixOS module for the JT MCP Server — JobTread PAVE API interface for Claude. Manages the standalone systemd service (SSE transport) and provides options consumed by the hwc-sys gateway (stdio backend mode).

## Boundaries
- Manages: systemd service definition, environment/secrets wiring, SSE/stdio transport config, security hardening
- Does NOT manage: the TypeScript server source code (-> /opt/business/jt-mcp/), Caddy reverse proxy routes (-> domains/networking/), secret declarations (-> domains/secrets/)

## Structure
```
mcp/
├── index.nix              # NixOS module: options + systemd service + validation
├── README.md              # This file
└── pave_api_reference/    # PAVE API documentation
```

## Changelog
- 2026-04-12: Rename heartwood-mcp→jt-mcp (systemd services, runtime paths, descriptions). 56 tools after consolidation (was 71).
- 2026-03-25: Initial creation — NixOS module for JT MCP Server (Phase 1: JT tools)
