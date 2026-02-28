# AI MCP

## Purpose
Model Context Protocol servers for AI tool integration.

## Boundaries
- Manages: MCP server configurations, tool definitions
- Does NOT manage: LLM inference → `ollama/`, UI → `open-webui/`

## Structure
```
mcp/
├── default.nix    # Package/overlay
├── index.nix      # MCP implementation
└── options.nix    # MCP options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
