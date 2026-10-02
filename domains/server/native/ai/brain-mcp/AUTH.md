# Brain MCP access

## Public clients

Use `https://brain-mcp.iheartwoodcraft.com/mcp`. The OAuth gateway advertises
`https://auth-mcp.iheartwoodcraft.com` as its authorization server. Leave the
client ID and secret blank in a connector that supports dynamic registration.
Cloudflare Access protects the human login at `/authorize`. The gateway issues
30-day access tokens and non-expiring refresh tokens, and sends its separate
Service Auth credential to `brain-origin.iheartwoodcraft.com/mcp`.

The replacement origin rejects anonymous requests and the legacy gateway
credential (verified 2026-10-02). Its new credential is encrypted in
`domains/secrets/parts/services/hwc-gateway-com.age`. The Worker configuration
and Access resource inventory live in `~/600_apps/hwc-mcp-gateway/`.

## Private clients

On hwc-work, use `http://127.0.0.1:9876/mcp`. Tailnet clients use the generated
Brain MCP endpoint from Nix; the Caddy HTTPS route is port 23443. The process
has no app-level Bearer check. Private access trusts the tailnet boundary.

## Retirement state

The old `.me` gateway remains during client reconnection. Historical bare
`brain.*` aliases are separate routes; they were found to allow anonymous tool
discovery and must be protected or removed after their consumers are reconciled.
Do not treat an MCP portal policy as protection of an upstream hostname.
Use the replacement gateway when adding a public client.
