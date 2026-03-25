# domains/automation/n8n/

## Purpose

n8n workflow automation platform running as a Podman container. Handles alert routing, webhook processing, business integrations (JobTread, Slack), and general workflow automation. Exposed via Tailscale Funnel for external access.

## Boundaries

- **Manages**: n8n container, Tailscale Funnel exposure, secret injection, firewall rules
- **Does NOT manage**: Workflow JSON definitions (→ `parts/workflows/`), estimator integration (→ `parts/estimator-integration/`), MQTT broker (→ `domains/automation/mqtt/`)

## Structure

```
domains/automation/n8n/
├── index.nix          # Option definitions, firewall, Tailscale Funnel services
├── sys.nix            # Container definition, env file generation, tmpfiles
├── README.md          # This file
└── parts/
    ├── estimator-integration/  # Estimator webhook integration
    │   └── README.md
    └── workflows/              # n8n workflow JSON definitions
        └── README.md
```

## Namespace

`hwc.automation.n8n.*`

## Configuration

```nix
hwc.automation.n8n = {
  enable = true;
  image = "docker.io/n8nio/n8n:latest";
  port = 5678;
  webhookUrl = "https://hwc.ocelot-wahoo.ts.net";
  dataDir = "/var/lib/hwc/n8n";
  timezone = "America/Denver";

  database.type = "sqlite";

  encryption.keyFile = config.age.secrets.n8n-encryption-key.path;

  secrets = {
    estimatorApiKeyFile = config.age.secrets.estimator-api-key.path;
    jobtreadGrantKeyFile = config.age.secrets.jobtread-grant-key.path;
    slackWebhookUrlFile = config.age.secrets.slack-webhook-url.path;
    anthropicApiKeyFile = config.age.secrets.anthropic-api-key.path;
  };

  owner = {
    email = "eric@iheartwoodcraft.com";
    firstName = "Eric";
    lastName = "Okeefe";
    passwordHashFile = config.age.secrets.n8n-owner-password-hash.path;
  };

  funnel = {
    enable = true;
    port = 8443;    # Must be 443, 8443, or 10000 (Funnel limitation)
  };
};
```

## Dependencies

- **agenix secrets**: encryption key, owner password hash, various API keys
- **Tailscale** — Funnel services expose n8n publicly on ports 10000 and optionally 8443

## Access

| Endpoint | URL |
|----------|-----|
| Internal | `http://127.0.0.1:5678` |
| Tailscale | `https://hwc.ocelot-wahoo.ts.net:5678` |
| Public (Funnel) | `https://hwc.ocelot-wahoo.ts.net:10000` |
| Full access (Funnel) | `https://hwc.ocelot-wahoo.ts.net:8443` (if funnel.enable) |

## Systemd Units

- `podman-n8n.service` — main n8n container (generates secrets env file in preStart)
- `tailscale-funnel-n8n.service` — public Funnel on port 10000
- `tailscale-funnel-n8n-full.service` — full access Funnel (optional)

## Changelog

- 2026-03-25: Created README per Law 12
