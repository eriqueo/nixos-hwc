# MCP Server Client Configuration

Your NixOS MCP filesystem server is now running and accessible!

## Endpoint Information

- **Server URL**: `https://hwc.ocelot-wahoo.ts.net/mcp/sse`
- **Access**: Tailscale network only (secure, no public internet exposure)
- **Transport**: MCP over HTTP (Server-Sent Events)
- **Scope**:
  - Read/Write: `/home/eric/.nixos` (your NixOS configuration)
  - Read/Write: `/home/eric/.nixos-mcp-drafts` (for LLM-proposed changes)

## Client Configuration Examples

### Claude Desktop (Anthropic)

Add to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
**Linux**: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "nixos-filesystem": {
      "url": "https://hwc.ocelot-wahoo.ts.net/mcp/sse",
      "transport": {
        "type": "sse"
      }
    }
  }
}
```

### Python MCP Client

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.sse import sse_client
import httpx

async with httpx.AsyncClient() as http_client:
    async with sse_client(
        "https://hwc.ocelot-wahoo.ts.net/mcp/sse",
        http_client
    ) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # List available tools
            tools = await session.list_tools()
            print(f"Available tools: {tools}")

            # Read a file
            result = await session.call_tool(
                "read_file",
                arguments={"path": "/home/eric/.nixos/flake.nix"}
            )
            print(result)
```

### Generic MCP Client Configuration

For any MCP-compatible client:

- **Protocol**: MCP over HTTP (SSE transport)
- **Endpoint**: `https://hwc.ocelot-wahoo.ts.net/mcp/sse`
- **Authentication**: None (secured by Tailscale network boundary)
- **Available Operations**:
  - `read_file` - Read file contents
  - `write_file` - Write file contents
  - `list_directory` - List directory contents
  - `create_directory` - Create a new directory
  - `move_file` - Move/rename files
  - `search_files` - Search for files by pattern

## Testing the Connection

### From Command Line (curl)

```bash
# Test basic connectivity
curl -I https://hwc.ocelot-wahoo.ts.net/mcp/sse

# You should see:
# HTTP/2 200
# content-type: text/event-stream
```

### From Your Mobile Device

1. Ensure your mobile device is connected to Tailscale
2. Configure your MCP-capable mobile app with:
   - URL: `https://hwc.ocelot-wahoo.ts.net/mcp/sse`
   - Transport: SSE (Server-Sent Events)

## Security Notes

- ✅ Accessible only via Tailscale (no public internet exposure)
- ✅ HTTPS with Tailscale TLS certificates
- ✅ Read-only access to `/home/eric/.nixos`
- ✅ Write access isolated to `/home/eric/.nixos-mcp-drafts`
- ⚠️ No authentication required (relies on Tailscale network boundary)

## Recommended Workflow

1. **LLM reads your NixOS config**: Files from `/home/eric/.nixos`
2. **LLM proposes changes**: Writes to `/home/eric/.nixos-mcp-drafts/`
3. **You review**: Check the proposed changes in the drafts directory
4. **You apply**: Manually copy approved changes to your actual config

## Service Status

Check if the MCP services are running:

```bash
# On your server
systemctl status mcp-proxy.service
systemctl status caddy.service

# Check listening port
ss -tlnp | grep 6001
```

## Troubleshooting

### Can't connect from client

1. Verify Tailscale is connected: `tailscale status`
2. Check MCP proxy is running: `systemctl status mcp-proxy`
3. Check Caddy is running: `systemctl status caddy`
4. Test endpoint: `curl -I https://hwc.ocelot-wahoo.ts.net/mcp/sse`

### MCP server not responding

```bash
# Check logs
journalctl -u mcp-proxy.service -f

# Restart if needed
sudo systemctl restart mcp-proxy.service
```

## Expanding to Other Services

To add additional MCP servers in the future (containers, systemd, databases), you can use the same reusable template in `/home/eric/.nixos/domains/server/ai/mcp/default.nix`.

The `mkMcpService` function makes it easy to create new MCP servers with proper security hardening.
