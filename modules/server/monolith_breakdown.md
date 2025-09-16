#!/usr/bin/env bash
# Refactor monolith -> modular container services
# Writes an opinionated, repeatable scaffold under modules/services/containers/
# Safe to re-run: it won't overwrite existing files.

set -euo pipefail

ROOT="modules/services/containers"
SHARED="$ROOT/_shared"
mkdir -p "$ROOT" "$SHARED"

# -------- helpers --------
mkfile() {
  local path="$1"
  shift || true
  if [[ -e "$path" ]]; then
    echo "keep   $path"
  else
    echo "create $path"
    mkdir -p "$(dirname "$path")"
    printf "%s\n" "$*" > "$path"
  fi
}

# -------- shared: lib.nix --------
mkfile "$SHARED/lib.nix" "$(cat <<'NIX'
{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf mkDefault mkMerge concatLists concatStringsSep;
in
{
  options.hwc.services.shared = {
    # accumulator used by services to publish reverse proxy routes
    routes = mkOption {
      internal = true;
      type = types.listOf (types.attrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes (service-provided).";
    };
  };

  # exported helpers
  config.hwc.services.shared.lib = rec {
    mkBoolOption = { default ? false, description ? "" }:
      mkOption { type = types.bool; inherit default description; };

    mkImageOption = { default, description ? "" }:
      mkOption { type = types.str; inherit default description; };

    mkPathOption = { default ? null, description ? "" }:
      mkOption { type = types.nullOr types.path; inherit default description; };

    mkRoute = { path, upstream, stripPrefix ? false }:
      { inherit path upstream stripPrefix; };

    mkContainer = {
      name, image, networkMode ? "media", gpuEnable ? true,
      ports ? [], volumes ? [], environment ? {}, extraOptions ? [], dependsOn ? []
    }:
    let
      podmanNetworkOpts =
        if networkMode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ];
      gpuOpts =
        if (!gpuEnable) then []
        else if (config.hwc.infrastructure.hardware.gpu.accel or null) == "cuda" then [
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ] else [
          "--device=/dev/dri:/dev/dri"
        ];
      baseEnv = {
        PUID = "1000";
        PGID = "1000";
        TZ   = config.time.timeZone or "UTC";
      };
    in
    {
      "virtualisation.oci-containers.containers.${name}" = {
        inherit image;
        autoStart = true;
        inherit dependsOn;
        environment = baseEnv // environment;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ extraOptions ++ [ "--memory=2g" "--cpus=1.0" "--memory-swap=4g" ];
        ports = ports;
        volumes = volumes;
      };
    };
  };
}
NIX
)"

# -------- shared: network.nix --------
mkfile "$SHARED/network.nix" "$(cat <<'NIX'
{ lib, config, pkgs, ... }:
let
  mediaNetworkName = "media-network";
  podman = "${pkgs.podman}/bin/podman";
in
{
  systemd.services.init-media-network = {
    description = "Create podman media network (idempotent)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if ! ${podman} network ls --format "{{.Name}}" | grep -qx ${mediaNetworkName}; then
        ${podman} network create ${mediaNetworkName}
      else
        echo "${mediaNetworkName} exists"
      fi
    '';
  };
}
NIX
)"

# -------- shared: caddy.nix --------
mkfile "$SHARED/caddy.nix" "$(cat <<'NIX'
{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;
  routes = config.hwc.services.shared.routes;
  renderRoute = r:
    let
      path = r.path or "/";
      upstream = r.upstream;
      strip   = r.stripPrefix or false;
    in
      if strip then ''
        handle_path ${path}/* {
          reverse_proxy ${upstream}
        }
      '' else ''
        handle ${path} { redir ${path}/ 301 }
        route ${path}* {
          reverse_proxy ${upstream} {
            header_up Host {host}
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Port {server_port}
            header_up X-Forwarded-For {remote}
            header_up X-Real-IP {remote}
          }
        }
      '';
in
{
  options.hwc.services.reverseProxy = {
    enable = mkEnableOption "Aggregate service routes into a single Caddy vhost";
    domain = mkOption { type = types.str; default = "localhost"; };
  };

  config = mkIf config.hwc.services.reverseProxy.enable {
    services.caddy = {
      enable = true;
      virtualHosts."${config.hwc.services.reverseProxy.domain}".extraConfig =
        concatStringsSep "\n" (map renderRoute routes);
    };
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
NIX
)"

# -------- per-service scaffolder --------
scaffold_service() {
  local svc="$1"
  local imageDefault="$2"
  local ports="$3"   # json array of strings, e.g. '["127.0.0.1:7878:7878"]'
  local routePath="$4"  # e.g. "/radarr" (empty for none)
  local upstream="$5"   # e.g. "127.0.0.1:7878"

  local DIR="$ROOT/$svc"
  local PARTS="$DIR/parts"
  mkdir -p "$PARTS"

  # index.nix
  mkfile "$DIR/index.nix" "$(cat <<NIX
{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.${svc};
in
{
  options.hwc.services.containers.${svc} = {
    enable = mkEnableOption "${svc} container";
    image  = shared.mkImageOption { default = "${imageDefault}"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };

  imports = [
    ./parts/sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  config = mkIf cfg.enable { };
}
NIX
)"

  # sys.nix
  mkfile "$PARTS/sys.nix" "$(cat <<NIX
{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.${svc};
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "${svc}";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = ${ports};
      volumes = [ "/opt/downloads/${svc}:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
$([[ -n "$routePath" ]] && cat <<NIX2
    { # publish caddy route
      hwc.services.shared.routes = [
        (shared.mkRoute { path = "${routePath}"; upstream = "${upstream}"; stripPrefix = ${"false"}; })
      ];
    }
NIX2
)
  ]);
}
NIX
)"

  # parts stubs
  mkfile "$PARTS/config.nix" "{ }: {}"
  mkfile "$PARTS/scripts.nix" "{ }: {}"
  mkfile "$PARTS/pkgs.nix" "{ }: {}"
  mkfile "$PARTS/lib.nix" "{ }: {}"
}

# -------- scaffold infra + apps (opinionated defaults) --------
# images & routes reflect the monolith you shared
scaffold_service "gluetun" "qmcgaw/gluetun:latest" "[]" "" ""

# Download clients (no direct ports; gluetun publishes UIs)
scaffold_service "qbittorrent" "lscr.io/linuxserver/qbittorrent" "[]" "/qbt" "127.0.0.1:8080"
scaffold_service "sabnzbd"     "lscr.io/linuxserver/sabnzbd:latest" "[]" "/sab" "127.0.0.1:8081"

# *arr suite
scaffold_service "sonarr"   "lscr.io/linuxserver/sonarr:latest"   '["127.0.0.1:8989:8989"]' "/sonarr"  "127.0.0.1:8989"
scaffold_service "radarr"   "lscr.io/linuxserver/radarr:latest"   '["127.0.0.1:7878:7878"]' "/radarr"  "127.0.0.1:7878"
scaffold_service "lidarr"   "lscr.io/linuxserver/lidarr:latest"   '["127.0.0.1:8686:8686"]' "/lidarr"  "127.0.0.1:8686"
scaffold_service "prowlarr" "lscr.io/linuxserver/prowlarr:latest" '["127.0.0.1:9696:9696"]' "/prowlarr" "127.0.0.1:9696"

# Media / extras
scaffold_service "jellyfin" "lscr.io/linuxserver/jellyfin:latest" '["127.0.0.1:8096:8096"]' "/media" "127.0.0.1:8096"
scaffold_service "immich"   "ghcr.io/immich-app/immich-server:latest" "[]" "" ""
scaffold_service "slskd"    "slskd/slskd:latest" '["127.0.0.1:5030:5030"]' "/slskd" "127.0.0.1:5030"
scaffold_service "soularr"  "docker.io/mrusse08/soularr:latest" "[]" "" ""
scaffold_service "navidrome" "deluan/navidrome:latest" '["0.0.0.0:4533:4533"]' "/navidrome" "127.0.0.1:4533"
scaffold_service "caddy" "docker.io/library/caddy:latest" "[]" "" ""

# -------- Gluetun specifics (env from Agenix) --------
GLUE="$ROOT/gluetun/parts/sys.nix"
if ! grep -q "Gluetun specifics" "$GLUE"; then
  cat >> "$GLUE" <<'NIX'

  # Gluetun specifics: compose env file from Agenix, expose qbt/sab ports
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.services.gluetun-env = {
        description = "Compose Gluetun .env from Agenix secrets";
        before = [ "podman-gluetun.service" ];
        wantedBy = [ "podman-gluetun.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -e
          install -d -m 0700 -o root -g root /opt/downloads
          VPN_USER=$(cat ${config.age.secrets.vpn_user.path})
          VPN_PASS=$(cat ${config.age.secrets.vpn_pass.path})
          cat > /opt/downloads/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USER
OPENVPN_PASSWORD=$VPN_PASS
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
EOF
          chmod 600 /opt/downloads/.env
        '';
      };

      virtualisation.oci-containers.containers.gluetun = {
        extraOptions = [ "--cap-add=NET_ADMIN" "--device=/dev/net/tun:/dev/net/tun" "--network=media-network" "--network-alias=gluetun" ];
        environmentFiles = [ "/opt/downloads/.env" ];
        ports = [ "127.0.0.1:8080:8080" "127.0.0.1:8081:8085" ];
        volumes = [ "/opt/downloads/gluetun:/gluetun" ];
        environment = { TZ = config.time.timeZone or "UTC"; };
      };
    }
  ]);
NIX
fi

echo "Done. Next:"
echo "  - import _shared/network.nix and _shared/caddy.nix in your server profile"
echo "  - enable services via hwc.services.containers.<name>.enable = true;"
echo "  - set hwc.services.reverseProxy.{enable,domain}"





Solid scaffold. It’s close to “drop in and go.” A few fixes and hardening notes to make it correct, predictable, and easier to extend.

## High-impact fixes

1. Nix attrpath bug in `mkContainer`
   You’re using a **string** key with dots. That won’t populate the option tree. Use an attrpath:

```nix
# before (wrong): string key with dots
{
  "virtualisation.oci-containers.containers.${name}" = { ... };
}

# after (correct): attrpath
{
  virtualisation.oci-containers.containers.${name} = {
    inherit image;
    autoStart = true;
    inherit dependsOn;
    environment = baseEnv // environment;
    extraOptions = podmanNetworkOpts ++ gpuOpts ++ extraOptions ++ [
      "--memory=2g" "--cpus=1.0" "--memory-swap=4g"
    ];
    ports = ports;
    volumes = volumes;
  };
}
```

Minimal patch inside `_shared/lib.nix` → `mkContainer` function body.

2. Safer route aggregation expression
   Lists do merge by concatenation, but being explicit avoids surprises:

```nix
# in per-service parts/sys.nix, when publishing a route
{
  hwc.services.shared.routes = lib.mkAfter [
    (shared.mkRoute { path = "/sonarr"; upstream = "127.0.0.1:8989"; stripPrefix = false; })
  ];
}
```

3. Consistency: reverse proxy option naming
   Your doc uses `caddy.hostname`, the shared module uses `reverseProxy.domain`. Pick one. If you keep the shared module, update your profile example to:

```nix
hwc.services.reverseProxy.enable = true;
hwc.services.reverseProxy.domain = "media.example.internal";
```

…and remove the older `caddy.hostname` line to avoid drift.

## Tightening & quality-of-life

* `mkfile` permissions: ensure deterministic perms.

```bash
printf "%s\n" "$*" > "$path"
chmod 0644 "$path"
```

* Shell heredoc: you’re safe because each `mkfile` call passes a single argument; `printf "%s\n" "$*"` works. If you ever pass multiple args, switch to `printf "%s\n" "$@"` to avoid joining.

* GPU flags: current heuristic checks a custom key `config.hwc.infrastructure.hardware.gpu.accel`. Good. Consider a `mkBoolOption` like `gpu.enableDefault` at the **service** level to force-disable on containers that never need GPU.

* Podman network oneshot: good idempotency. Consider adding `Restart=no` (implicit for oneshot) and `RemainAfterExit=yes` to avoid repeat runs during daemon reloads.

```nix
serviceConfig = {
  Type = "oneshot";
  RemainAfterExit = true;
};
```

* Caddy route rendering: your `redir` + `route` block is fine. If you plan to use path stripping more, keep `handle_path` branch (already present).

* `ports` injection in the scaffold: you’re interpolating Nix lists correctly (e.g., `'["127.0.0.1:8989:8989"]'`). It’s brittle if someone passes an empty string. Your defaults use `"[]"`, which is fine.

* Default volumes: `"/opt/downloads/${svc}:/config"` as a universal default is opinionated. It’s convenient, but you’ll want per-service overrides for data directories (e.g., jellyfin caches, navidrome music root). The scaffold already allows editing later.

* Gluetun env composition: good pattern. Minor hardening:

  * Protect against missing secrets (exit with message).
  * Use `install -m 0600` for the `.env`.
  * Don’t echo country hardcoded unless that’s intended.

```nix
script = ''
  set -euo pipefail
  install -d -m 0700 -o root -g root /opt/downloads
  : ''${config.age.secrets.vpn_user.path:?vpn_user secret missing}
  : ''${config.age.secrets.vpn_pass.path:?vpn_pass secret missing}
  VPN_USER=$(cat ${config.age.secrets.vpn_user.path})
  VPN_PASS=$(cat ${config.age.secrets.vpn_pass.path})
  umask 177
  cat > /opt/downloads/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USER
OPENVPN_PASSWORD=$VPN_PASS
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
EOF
'';
```

* Gluetun published ports: you expose `127.0.0.1:8080:8080` and `127.0.0.1:8081:8085`. Confirm those align with your qBittorrent/SAB internal mappings (your qbt UI at `/qbt` expects 8080; SAB at `/sab` expects 8081). Looks consistent.

## Optional improvements (future-proofing)

* Add small option builders for ports/volumes to reduce inline literals:

```nix
mkStrListOption = { default ? [], description ? "" }:
  mkOption { type = types.listOf types.str; inherit default description; };

# then in service options:
ports = mkStrListOption { default = []; description = "Host port mappings"; };
volumes = mkStrListOption { default = []; description = "Bind mounts"; };
```

* Provide a tiny `readSecretsEnv` helper in `_shared/lib.nix` that accumulates an envfile from multiple age secrets (common in services with multiple creds).

* Consider `systemd` deps for services that need the network created first:

```nix
systemd.services.podman-${svc}.after = [ "init-media-network.service" ];
systemd.services.podman-${svc}.wants = [ "init-media-network.service" ];
```

* If you routinely run some services without GPU, set `gpu.enable = false;` in the scaffold lines for those.

## TL;DR patches to apply now

* Fix the attrpath in `_shared/lib.nix::mkContainer` (most important).
* Use `mkAfter` when adding routes (clarity).
* Normalize on `hwc.services.reverseProxy.{enable,domain}` in your profile.
* Set file perms in `mkfile`.

Everything else is optional polish.
