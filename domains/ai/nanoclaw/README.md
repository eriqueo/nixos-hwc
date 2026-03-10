# domains/ai/nanoclaw/

## Purpose

NanoClaw AI agent orchestrator - a lightweight system for running Claude agents in isolated containers with Slack integration. Spawns agent containers via Podman socket (container-in-container pattern) with controlled access to host paths.

## Boundaries

- **Manages**: Container orchestration, Slack Socket Mode connection, mount allowlist configuration, agent group definitions
- **Does NOT manage**: Anthropic API keys (-> `domains/secrets/`), Podman runtime (-> `domains/server/`), media network (-> `domains/networking/`)

## Structure

```
domains/ai/nanoclaw/
├── default.nix    # Options (enable, image, dataDir, slack, groups)
├── sys.nix        # Container implementation and mount configs
└── README.md      # This file
```

## Configuration

```nix
hwc.ai.nanoclaw = {
  enable = true;
  slack.enable = true;  # Inject Slack tokens from agenix

  # Declarative group configurations with container mount access
  groups = {
    server-admin = {
      slackChannel = "C09V251ABV1";
      description = "Server administration agent";
      additionalMounts = [
        { hostPath = "/home/eric/.nixos"; containerPath = "nixos"; readonly = false; }
        { hostPath = "/mnt/media"; containerPath = "media"; readonly = false; }
        { hostPath = "/var/log"; containerPath = "logs"; readonly = true; }
      ];
    };
  };
};
```

## Runtime Paths

| Path | Purpose |
|------|---------|
| `/opt/ai/nanoclaw/` | Main data directory |
| `/opt/ai/nanoclaw/config/` | Allowlist configs (mount-allowlist.json, sender-allowlist.json) |
| `/opt/ai/nanoclaw/groups/` | Agent group definitions |
| `/opt/ai/nanoclaw/data/sessions/` | Agent session data |

## Agent Container Mounts

Paths in `additionalMounts` appear inside agent containers at `/workspace/extra/<containerPath>`:

| Container Path | Host Path | Access |
|----------------|-----------|--------|
| `/workspace/extra/nixos` | `/home/eric/.nixos` | read-write |
| `/workspace/extra/media` | `/mnt/media` | read-write |
| `/workspace/extra/logs` | `/var/log` | read-only |

## Changelog

- 2026-03-10: Added declarative group configuration with additionalMounts support; fixed mount allowlist path issue (now mounted to both /root/.config/nanoclaw and /home/eric/.config/nanoclaw)
