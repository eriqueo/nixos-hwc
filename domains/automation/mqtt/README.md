# domains/automation/mqtt/

## Purpose

Mosquitto MQTT broker providing a lightweight message bus for service integration. Primarily used by Frigate for detection events, consumed by n8n workflows via an optional webhook bridge.

## Boundaries

- **Manages**: Mosquitto native service, MQTT-to-webhook bridge for n8n
- **Does NOT manage**: Frigate (→ `domains/media/frigate/`), n8n workflows (→ `domains/automation/n8n/`)

## Structure

```
domains/automation/mqtt/
├── index.nix     # Options, Mosquitto config, webhook bridge service
└── README.md     # This file
```

## Namespace

`hwc.automation.mqtt.*`

## Configuration

```nix
hwc.automation.mqtt = {
  enable = true;
  port = 1883;
  dataDir = "/var/lib/hwc/mosquitto";

  webhookBridge = {
    enable = true;
    topic = "frigate/events";
    webhookUrl = "http://127.0.0.1:5678/webhook/frigate-events";
  };
};
```

## Details

- Runs as **native NixOS service** (not containerized) — simpler for a local-only broker
- Binds to `127.0.0.1` only — no external access
- Anonymous access enabled (safe on localhost)
- Webhook bridge subscribes to MQTT topic and forwards JSON payloads to n8n via HTTP POST

## Systemd Units

- `mosquitto.service` — MQTT broker (native NixOS)
- `mqtt-webhook-bridge.service` — forwards MQTT events to n8n webhook (optional)

## Changelog

- 2026-03-25: Created README per Law 12
