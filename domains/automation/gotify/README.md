# domains/automation/gotify/

## Purpose

Gotify CLI tool (`hwc-gotify-send`) for sending push notifications from any machine or service
to the self-hosted gotify server. Replaces the previous ntfy CLI.

## Boundaries

- **Manages**: `hwc-gotify-send` CLI tool, gotify client configuration
- **Does NOT manage**: gotify server (→ `domains/alerts/parts/server.nix`), alertmanager bridge (→ `domains/alerts/parts/gotify-bridge.nix`)

## Structure

```
gotify/
├── index.nix    # hwc.automation.gotify.* options + hwc-gotify-send script
└── README.md    # This file
```

## Usage

```bash
# Basic send (uses default token file)
hwc-gotify-send "Title" "Message body"

# Override token file (different gotify app)
hwc-gotify-send --token-file /run/agenix/gotify-token-backup "Backup Done" "Details..."

# Set priority (0=min, 5=normal, 10=max)
hwc-gotify-send --priority 10 "CRITICAL" "System is down"
```

## Configuration

```nix
hwc.automation.gotify = {
  enable = true;
  serverUrl = "https://hwc.ocelot-wahoo.ts.net:2586";
  defaultTokenFile = config.age.secrets.gotify-token-alerts.path;
  defaultPriority = 5;
  hostTag = true;  # Prepends [host: hostname] to messages
};
```

## Changelog

- 2026-03-29: Created — replaces domains/automation/ntfy/ with gotify JSON API and per-app token model
