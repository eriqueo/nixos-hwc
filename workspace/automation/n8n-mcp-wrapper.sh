#!/usr/bin/env bash
# Wrapper for n8n-mcp that reads API key from agenix secret
# Uses stable install at /opt/n8n-mcp (patched for JSON responses)
export N8N_API_KEY=$(cat /run/agenix/n8n-api-key)
export N8N_API_URL="http://localhost:5678"
export MCP_MODE="stdio"
export LOG_LEVEL="error"
export NO_COLOR=1
export DISABLE_CONSOLE_OUTPUT="true"
exec /run/current-system/sw/bin/node /opt/n8n-mcp/node_modules/n8n-mcp/dist/mcp/index.js "$@" 2>/dev/null
