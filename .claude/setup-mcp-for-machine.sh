#!/usr/bin/env bash
# Setup machine-specific MCP configuration

HOSTNAME=$(hostname)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MCP_LINK="$REPO_ROOT/.mcp.json"

case "$HOSTNAME" in
  "hwc-laptop"|"laptop")
    echo "Configuring MCP for laptop..."
    ln -sf .mcp.laptop.json "$MCP_LINK"
    echo "✓ Linked .mcp.json → .mcp.laptop.json"
    ;;
  "hwc-server"|"server")
    echo "Configuring MCP for server..."
    ln -sf .mcp.server.json "$MCP_LINK"
    echo "✓ Linked .mcp.json → .mcp.server.json"
    ;;
  *)
    echo "⚠ Unknown hostname: $HOSTNAME"
    echo "Using laptop config as default..."
    ln -sf .mcp.laptop.json "$MCP_LINK"
    ;;
esac

echo ""
echo "Current MCP config:"
ls -la "$MCP_LINK"
