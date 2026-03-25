# Heartwood MCP Server

Unified MCP (Model Context Protocol) server for Heartwood Craft's business systems. Exposes every business operation as a typed, documented MCP tool.

## Architecture

- **Tier 1**: Atomic operations — direct API wrappers (63 JT tools, Paperless, Firefly)
- **Tier 2**: Compound operations — n8n-backed multi-step workflows
- **Tier 3**: Query & intelligence — Postgres views, server commands

## Quick Start

```bash
# Install dependencies
npm install

# Build
npm run build

# Run (stdio mode, for Claude Code)
JT_GRANT_KEY=your-key node dist/index.js

# Run (SSE mode, for remote access)
TRANSPORT=sse SSE_PORT=6100 JT_GRANT_KEY=your-key node dist/index.js

# Development
npm run dev
```

## Project Structure

```
src/
├── index.ts              # Server entry point (stdio + SSE transport)
├── config.ts             # Environment-based configuration
├── logging/
│   └── logger.ts         # Structured JSON logger (stderr)
├── pave/
│   ├── types.ts          # PAVE API type definitions
│   ├── client.ts         # PAVE client (auth, retries, error detection)
│   ├── fields.ts         # Reusable field definitions per entity
│   └── index.ts          # Barrel export
└── tools/
    ├── registry.ts       # Tool registry and ToolDef interface
    └── jt/
        ├── index.ts      # All 63 JT tools aggregated
        ├── accounts.ts   # Accounts & Contacts (6 tools)
        ├── locations.ts  # Locations (2 tools)
        ├── jobs.ts       # Jobs (5 tools)
        ├── budget.ts     # Budget & Cost Items (9 tools)
        ├── documents.ts  # Documents (5 tools)
        ├── payments.ts   # Payments (2 tools)
        ├── tasks.ts      # Tasks (7 tools)
        ├── time-entries.ts   # Time Entries (4 tools)
        ├── daily-logs.ts     # Daily Logs (4 tools)
        ├── files.ts          # Files (7 tools)
        ├── job-folders.ts    # Job Folders (1 tool)
        ├── comments.ts       # Comments (3 tools)
        ├── dashboards.ts     # Dashboards (3 tools)
        ├── custom-fields.ts  # Custom Fields & Search (2 tools)
        └── org-users.ts      # Organization & Users (3 tools)
```

## NixOS Deployment

The NixOS module lives at `domains/ai/mcp/heartwood/index.nix`. Enable with:

```nix
hwc.ai.mcp.enable = true;
hwc.ai.mcp.heartwood.enable = true;
```

## Date/Time Convention

- **Date-only fields** (YYYY-MM-DD): Interpreted in the org's timezone (America/Denver)
- **Datetime fields**: Must include timezone offset in ISO 8601 format (e.g., `2026-03-25T08:00:00-06:00`)
- **Time entries**: Both `startedAt` and `endedAt` require full ISO 8601 with timezone

## Implementation Status

- [x] Phase 1: JT MCP Server (63 tools via PAVE API)
- [ ] Phase 2: Paperless-ngx + Firefly III tools
- [ ] Phase 3: Compound operations (n8n-backed Tier 2)
- [ ] Phase 4: Query & intelligence tools (Postgres Tier 3)
