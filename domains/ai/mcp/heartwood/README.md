# Heartwood MCP Server

## Purpose
NixOS module for the Heartwood MCP Server — a unified MCP interface to all business systems (JobTread, Paperless-ngx, Firefly III). Replaces the datax JT MCP connector ($50/month) and centralizes all API translation, auth, error handling, and logging.

## Boundaries
- Manages: systemd service definition, environment/secrets wiring, SSE/stdio transport config, security hardening
- Does NOT manage: the TypeScript server source code (-> workspace/projects/heartwood-mcp/), Caddy reverse proxy routes (-> domains/networking/), secret declarations (-> domains/secrets/)

## Structure
```
heartwood/
├── index.nix    # NixOS module: options + systemd service + validation
└── README.md    # This file
```

## Changelog
- 2026-03-25: Initial creation — NixOS module for Heartwood MCP Server (Phase 1: JT tools)
