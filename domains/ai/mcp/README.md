# AI MCP

## Purpose
Filesystem MCP services and their optional HTTP proxy. The parent enable gates both service and route availability.

## Structure
`index.nix` owns options, the service template and shared filesystem invocation. `proxy.active` and `reverseProxy.active` are read-only derived flags consumed by networking. `reverseProxy.authType` remains a legacy compatibility input and configures no authentication.

## Boundaries
The current tool gateway belongs to `domains/system/mcp`. This module does not own JobTread, local inference or an application source checkout.

## Changelog
- 2026-11-09: Centralize shared service inputs and effective enable flags; remove the pass-through import wrapper and stale Heartwood server map.
