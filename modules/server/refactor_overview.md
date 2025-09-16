# HWC Service Modules — Structure, Purpose, and How It Works

This refactor turns the old “monolith” into a **predictable, modular, and composable** framework.
Every service (app or infra) is a **self‑contained folder** with a standard set of “parts.”
Infra like **gluetun** (VPN) and **caddy** (reverse proxy) live beside apps and are wired the same way.

---

## Goals

- **One‑stop shop per service**: Everything it needs (container, files, scripts, firewall).
- **No duplication**: Reusable helpers in `containers/_shared`.
- **Domain separation**: `parts/sys.nix` (systemd/podman), `parts/config.nix` (files), etc.
- **Server‑only**: No Home‑Manager in this layer.
- **Agenix** for secrets (read from `/run/agenix/*`).

---

## Layout (per service)

```
modules/services/containers/<service>/
├─ index.nix      # options + imports all parts
└─ parts/
   ├─ sys.nix     # system bits: podman containers, systemd units, firewall
   ├─ config.nix  # config files rendered to disk (YAML/JSON/env/templates)
   ├─ scripts.nix # small helper scripts (writeShellScriptBin / oneshots)
   ├─ pkgs.nix    # packages the service needs (curl, jq, ffmpeg, …)
   └─ lib.nix     # tiny service‑local helpers (optional)
```

### Shared toolbox

```
modules/services/containers/_shared/
├─ lib.nix        # mkContainer, GPU flags, route builder, option helpers
└─ network.nix    # creates podman "media-network" once (oneshot)
```

- `_shared/lib.nix` provides:
  - `mkContainer { … }` — thin helper to build `virtualisation.oci-containers.containers.<name>`
    with correct **networking** (`"media"` or `"vpn"`), optional **GPU**, plus common flags.
  - `mkImageOption`, `mkPathOption`, `mkBoolOption` — consistent option builders for each service.
  - `mkRoute { path; upstream; stripPrefix ? false; }` — small record apps use to publish reverse‑proxy routes.
- `_shared/network.nix`:
  - **Creates** (idempotently) a user‑defined podman network: `media-network` for non‑VPN services.

---

## Networking model

- **media network**: default shared user‑defined podman network `media-network`.
- **vpn network**: service shares the **gluetun** container’s network namespace  
  (`--network=container:gluetun`). Downloaders behind VPN **do not** bind ports directly;
  **gluetun** publishes UIs on localhost.

Choose with `network.mode = "media"` or `"vpn"` in the service options.

---

## Reverse proxy model (Caddy)

Each app **publishes routes**:

```nix
hwc.services.containers.reverseProxy.routes = lib.mkAfter [
  (shared.mkRoute { path = "/sonarr"; upstream = "127.0.0.1:8989"; })
];
```

The **Caddy** module then **collects all routes** into one vhost config — no more giant monolith Caddyfile.

---

## Secrets (Agenix)

Declare in Nix:

```nix
age.secrets.vpn_username.file = ../../../secrets/vpn_username.age;
age.secrets.vpn_password.file = ../../../secrets/vpn_password.age;
```

Read at runtime from `/run/agenix/vpn_username` etc. inside oneshots or scripts.

---

## Enabling services (example profile)

```nix
# profiles/server-media.nix
{
  imports = [
    ../modules/services/containers/_shared/network.nix
    ../modules/services/containers/caddy
    ../modules/services/containers/gluetun
    ../modules/services/containers/qbittorrent
    ../modules/services/containers/sonarr
    ../modules/services/containers/radarr
    ../modules/services/containers/lidarr
    ../modules/services/containers/prowlarr
    ../modules/services/containers/jellyfin
    ../modules/services/containers/navidrome
    ../modules/services/containers/slskd
    ../modules/services/containers/soularr
    ../modules/services/containers/immich
    ../modules/services/containers/frigate
    # ../modules/services/containers/obsidian  # if used on server
  ];

  hwc.services.containers = {
    caddy.enable      = true;
    caddy.hostname    = "media.example.internal";

    gluetun.enable    = true;

    qbittorrent.enable = true;  qbittorrent.network.mode = "vpn";
    sonarr.enable      = true;  sonarr.network.mode = "media";
    radarr.enable      = true;
    lidarr.enable      = true;
    prowlarr.enable    = true;
    jellyfin.enable    = true;
    navidrome.enable   = true;
    slskd.enable       = true;
    soularr.enable     = true;
    immich.enable      = true;
    frigate.enable     = true;
  };
}
```

---

## Mental model

- **Every service is a folder**: self‑contained and importable anywhere.
- **Shared toolbox** prevents repeating GPU/network/option code.
- **Infra is just another service**: apps depend on it through options (e.g., `network.mode = "vpn"`).
- **No Home‑Manager** here; this is a server‑side module layer only.



Here’s a structured write-up of your **HWC Service Modules** refactor. I’m treating it as a reference doc you can drop into your repo or Obsidian.

---

# HWC Service Modules — Structure, Purpose, and How It Works

This refactor turns the old “monolith” into a **predictable, modular, and composable** framework.
Every service (app or infra) is a **self-contained folder** with a standard set of “parts.”
Infra like **gluetun** (VPN) and **caddy** (reverse proxy) live beside apps and are wired the same way.

---

## Goals

* **One-stop shop per service**: Everything it needs (container, files, scripts, firewall).
* **No duplication**: Reusable helpers in `containers/_shared`.
* **Domain separation**: `parts/sys.nix` (systemd/podman), `parts/config.nix` (files), etc.
* **Server-only**: No Home-Manager in this layer.
* **Agenix** for secrets (read from `/run/agenix/*`).

---

## Layout (per service)

```
modules/services/containers/<service>/
├─ index.nix      # options + imports all parts
└─ parts/
   ├─ sys.nix     # system bits: podman containers, systemd units, firewall
   ├─ config.nix  # config files rendered to disk (YAML/JSON/env/templates)
   ├─ scripts.nix # small helper scripts (writeShellScriptBin / oneshots)
   ├─ pkgs.nix    # packages the service needs (curl, jq, ffmpeg, …)
   └─ lib.nix     # tiny service-local helpers (optional)
```

### Shared toolbox

```
modules/services/containers/_shared/
├─ lib.nix        # mkContainer, GPU flags, route builder, option helpers
└─ network.nix    # creates podman "media-network" once (oneshot)
```

* `_shared/lib.nix` provides:

  * `mkContainer { … }` — thin helper to build `virtualisation.oci-containers.containers.<name>`
    with correct **networking** (`"media"` or `"vpn"`), optional **GPU**, plus common flags.
  * `mkImageOption`, `mkPathOption`, `mkBoolOption` — consistent option builders for each service.
  * `mkRoute { path; upstream; stripPrefix ? false; }` — small record apps use to publish reverse-proxy routes.
* `_shared/network.nix`:

  * **Creates** (idempotently) a user-defined podman network: `media-network` for non-VPN services.

---

## Networking model

* **media network**: default shared user-defined podman network `media-network`.
* **vpn network**: service shares the **gluetun** container’s network namespace
  (`--network=container:gluetun`). Downloaders behind VPN **do not** bind ports directly;
  **gluetun** publishes UIs on localhost.

Choose with `network.mode = "media"` or `"vpn"` in the service options.

---

## Reverse proxy model (Caddy)

Each app **publishes routes**:

```nix
hwc.services.containers.reverseProxy.routes = lib.mkAfter [
  (shared.mkRoute { path = "/sonarr"; upstream = "127.0.0.1:8989"; })
];
```

The **Caddy** module then **collects all routes** into one vhost config — no more giant monolith Caddyfile.

---

## Secrets (Agenix)

Declare in Nix:

```nix
age.secrets.vpn_username.file = ../../../secrets/vpn_username.age;
age.secrets.vpn_password.file = ../../../secrets/vpn_password.age;
```

Read at runtime from `/run/agenix/vpn_username` etc. inside oneshots or scripts.

---

## Enabling services (example profile)

```nix
# profiles/server-media.nix
{
  imports = [
    ../modules/services/containers/_shared/network.nix
    ../modules/services/containers/caddy
    ../modules/services/containers/gluetun
    ../modules/services/containers/qbittorrent
    ../modules/services/containers/sonarr
    ../modules/services/containers/radarr
    ../modules/services/containers/lidarr
    ../modules/services/containers/prowlarr
    ../modules/services/containers/jellyfin
    ../modules/services/containers/navidrome
    ../modules/services/containers/slskd
    ../modules/services/containers/soularr
    ../modules/services/containers/immich
    ../modules/services/containers/frigate
    # ../modules/services/containers/obsidian  # if used on server
  ];

  hwc.services.containers = {
    caddy.enable      = true;
    caddy.hostname    = "media.example.internal";

    gluetun.enable    = true;

    qbittorrent.enable = true;  qbittorrent.network.mode = "vpn";
    sonarr.enable      = true;  sonarr.network.mode = "media";
    radarr.enable      = true;
    lidarr.enable      = true;
    prowlarr.enable    = true;
    jellyfin.enable    = true;
    navidrome.enable   = true;
    slskd.enable       = true;
    soularr.enable     = true;
    immich.enable      = true;
    frigate.enable     = true;
  };
}
```

---

## Mental model

* **Every service is a folder**: self-contained and importable anywhere.
* **Shared toolbox** prevents repeating GPU/network/option code.
* **Infra is just another service**: apps depend on it through options (e.g., `network.mode = "vpn"`).
* **No Home-Manager** here; this is a server-side module layer only.

---

This captures the structure, intention, and operational flow of your service modules.

Would you like me to extend this into a **contribution guide** (i.e. how to add a new service step-by-step with mkContainer, routes, secrets, etc.), or keep it as an architecture reference only?
