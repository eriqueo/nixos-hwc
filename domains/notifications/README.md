# Notifications Domain

Delivery infrastructure — how messages reach humans.

## Namespace

`hwc.notifications.*`

## Structure

```
notifications/
├── index.nix                    # Domain aggregator, webhook config, _internal exports
├── gotify/
│   ├── server.nix               # Gotify notification server container
│   ├── bridge.nix               # Alertmanager → Gotify bridge
│   └── igotify.nix              # iOS push notification relay (APNs)
├── send/
│   ├── gotify.nix               # hwc-gotify-send CLI tool
│   ├── slack-webhook.nix        # Webhook sender scripts (retry, fallback)
│   └── cli.nix                  # hwc-alert CLI tool
├── health.nix                   # Webhook endpoint health check timer
└── README.md
```

## Boundaries

**Owns:** All outbound notification delivery — Gotify server, webhook sending, CLI tools, health checks.

**Does NOT own:** Alert detection/thresholds (monitoring/alerts), workflow automation (automation/n8n).

## Key Options

| Option | Description |
|--------|-------------|
| `hwc.notifications.enable` | Enable notification delivery |
| `hwc.notifications.webhook.baseUrl` | n8n webhook base URL |
| `hwc.notifications.gotify.enable` | Enable Gotify server container |
| `hwc.notifications.gotify.bridge.enable` | Enable Alertmanager→Gotify bridge |
| `hwc.notifications.gotify.igotify.enable` | Enable iOS push relay |
| `hwc.notifications.send.gotify.enable` | Enable hwc-gotify-send CLI |
| `hwc.notifications.send.cli.enable` | Enable hwc-alert CLI |

## Changelog

- **2026-04-04**: Created from alerts + automation/gotify domain redistribution
