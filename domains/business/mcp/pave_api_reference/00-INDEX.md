# JobTread + Pave + MCP Reference Library

**Heartwood Craft · Bozeman, MT**
**Last updated:** 2026-03-26

This directory is the single source of truth for how JobTread's Pave API works, how MCP tools wrap it, and how to build/debug integrations. Designed for both human reference and AI agent consumption.

---

## Directory

| File | Purpose | When to use |
|---|---|---|
| `01-PAVE-FUNDAMENTALS.md` | How Pave works — not GraphQL, not REST. Query structure, auth, envelope format, field selection. | First read. Start here if you've never touched Pave. |
| `02-PAVE-OPERATIONS.md` | Every create/read/update/delete operation at the query root, with input signatures. | Looking up "can I do X?" or "what params does updateCostItem take?" |
| `03-PAVE-ENTITIES.md` | Every entity type (costItem, job, document, etc.) with their readable fields. | Looking up "what fields does a costItem have?" |
| `04-PAVE-ENUMS-AND-SCALARS.md` | All enum types (allowanceType, documentStatus, etc.) and scalar types with validation rules. | Looking up valid values for a field. |
| `05-MCP-ARCHITECTURE.md` | How MCP tools wrap Pave queries. The DataX pattern vs the Heartwood MCP pattern. Tool ↔ Pave mapping. | Building new MCP tools or debugging existing ones. |
| `06-HEARTWOOD-IDS.md` | All Heartwood Craft org-specific IDs: cost codes, cost types, units, custom fields. | Any operation that needs a Heartwood-specific ID. |
| `07-GOTCHAS.md` | Every known PAVE quirk, error pattern, and "I wasted 2 hours on this" lesson. | Debugging a 400 error or unexpected behavior. |
| `08-N8N-PATTERNS.md` | n8n-specific workflow patterns, node chaining, expression syntax. | Building or editing n8n workflows that hit Pave. |
| `09-GAP-ANALYSIS.md` | Known gaps between what Pave supports and what DataX/HWC MCP expose. Feature contribution targets. | Planning DataX contributions or HWC MCP additions. |

---

## How to use this

**Human:** Open the specific file for what you need. Start with `01` if you're new.

**AI Agent:** Read `01-PAVE-FUNDAMENTALS.md` first for query structure, then the specific file for your task. For debugging, read `07-GOTCHAS.md`. For building MCP tools, read `05-MCP-ARCHITECTURE.md`.

**Source of truth hierarchy:**
1. The Pave schema dump (stored separately — the raw YAML output from `schema: {}` at query root)
2. This reference library (distilled from the schema + battle-tested corrections)
3. The DataX MCP tool descriptions (may be incomplete — see `09-GAP-ANALYSIS.md`)
