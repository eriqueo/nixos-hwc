#!/usr/bin/env bash
# Wrapper for n8n-mcp that reads API key from agenix secret
export N8N_API_KEY=$(cat /run/agenix/n8n-api-key)
export N8N_API_URL="https://hwc.ocelot-wahoo.ts.net:2443"
export MCP_MODE="stdio"
export LOG_LEVEL="error"
export NO_COLOR=1
export DISABLE_CONSOLE_OUTPUT="true"
exec /run/current-system/sw/bin/node /home/eric/.npm-global/lib/node_modules/n8n-mcp/dist/mcp/index.js "$@" 2>/dev/null
