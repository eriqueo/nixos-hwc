# brain-mcp authentication

## Public path (recommended)

- URL: `https://brain.heartwoodcraft.me/mcp`
- Reachable from: anywhere
- Auth: **Cloudflare Access Managed OAuth** (Advanced settings → Managed OAuth toggle ON on the self-hosted Access application)
- Standards: RFC 8414 (OAuth 2.0 Authorization Server Metadata), RFC 9728 (OAuth 2.0 Protected Resource Metadata), Dynamic Client Registration, PKCE S256

### How claude.ai connects

1. claude.ai connector configured with **URL only** — no client ID or secret needed.
2. claude.ai hits `/mcp`, receives `401` with `WWW-Authenticate: Bearer realm="OAuth", resource_metadata=https://brain.heartwoodcraft.me/.well-known/cloudflare-access-protected-resource/mcp`.
3. claude.ai fetches `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource` to discover the authorization server (`polished-bush-c7f5.cloudflareaccess.com`).
4. claude.ai dynamically registers itself as an OAuth client via Cloudflare's DCR endpoint.
5. Cloudflare prompts the user to log in (browser).
6. claude.ai receives an OAuth access token (Bearer JWT).
7. All subsequent requests include the Bearer; Cloudflare validates → strips it → forwards to brain-mcp.

The brain-mcp process never sees the OAuth Bearer — Cloudflare strips it. App-level auth code was removed 2026-05-22.

## Headers-based path (automation / scripts)

For machine-to-machine access that can't do an interactive OAuth flow, use a Cloudflare Access **Service Token** policy on the same application:

```bash
curl -H "CF-Access-Client-Id: <id>.access" \
     -H "CF-Access-Client-Secret: <secret>" \
     https://brain.heartwoodcraft.me/mcp
```

Service tokens are created in: Cloudflare Zero Trust → Access → Service Credentials.

## Internal path (Tailscale / localhost)

- URL: `http://server:9876/mcp` (Tailscale alias `server`, IP `100.114.232.124`) or `http://127.0.0.1:9876/mcp` on the server itself.
- Reachable from: only the server's localhost and Tailscale tailnet devices.
- Auth: **none** at the app level. Trust boundary is the Tailscale identity layer (only paired devices can connect).
- Use case: laptop Claude Code, Charter-internal tooling, debugging.

## What does NOT work

- Passing `CF-Access-Client-Id` / `CF-Access-Client-Secret` as headers in claude.ai's MCP connector form. The "Advanced settings" fields on that form are OAuth client_id/client_secret, NOT HTTP headers. With Managed OAuth enabled, leave those fields blank — claude.ai uses Dynamic Client Registration.

## Same pattern on the other MCPs

Apply Managed OAuth to each Self-hosted Access app for parity:
- `leads.heartwoodcraft.me` (lead-scout) — done 2026-05-22
- `mcp.heartwoodcraft.me` (hwc_mcp) — done 2026-05-22
- Future MCPs: enable Managed OAuth on creation
