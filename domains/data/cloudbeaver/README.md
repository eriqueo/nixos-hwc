# domains/data/cloudbeaver/

## Purpose

CloudBeaver — web-based database management tool providing graphical PostgreSQL access from any device. Runs as a Podman container on the media network.

## Boundaries

- **Manages**: CloudBeaver container, workspace storage, firewall rules
- **Does NOT manage**: PostgreSQL (→ `domains/data/databases/`), reverse proxy (→ `domains/networking/`)

## Structure

```
domains/data/cloudbeaver/
├── index.nix     # Options, container, systemd deps, validation
└── README.md     # This file
```

## Namespace

`hwc.data.cloudbeaver.*`

## Configuration

```nix
hwc.data.cloudbeaver = {
  enable = true;
  image = "docker.io/dbeaver/cloudbeaver:latest";
  port = 8978;
  dataDir = "/var/lib/hwc/cloudbeaver";
};
```

## Dependencies

- **PostgreSQL** (`hwc.data.databases.postgresql.enable`) — required, validated by assertion
- **media-network** — container joins Podman media network

## Access

`http://127.0.0.1:8978` (localhost only, Caddy handles external access)

## Resources

- Memory: 1g, CPU: 0.5, Swap: 2g

## Systemd Units

- `podman-cloudbeaver.service` — container (after postgresql, init-media-network)

## Changelog

- 2026-03-25: Created README per Law 12
