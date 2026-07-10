# domains/monitoring/uptime-kuma/index.nix
#
# Uptime Kuma - Self-hosted uptime monitoring
#
# NAMESPACE: hwc.monitoring.uptime-kuma.*
#
# DEPENDENCIES:
#   - hwc.networking.shared.routes (for Caddy reverse proxy)
#
# PORTS:
#   - Internal: 3010 (container HTTP)
#   - External: 13543 (Caddy TLS termination)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.uptime-kuma;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.uptime-kuma = {
    enable = lib.mkEnableOption "Uptime Kuma - uptime monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Host port for Uptime Kuma web UI";
    };

    caddyPort = lib.mkOption {
      type = lib.types.port;
      default = 13543;
      description = "Caddy TLS port for Uptime Kuma";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "louislam/uptime-kuma:1";
      description = "Uptime Kuma container image";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/uptime-kuma";
      description = "Data directory for Uptime Kuma";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Uptime Kuma container
    # HWC-EXCEPTION(Law 5): infra container, not a media app
    # Justification: monitoring service with own state volume and localhost port; no media mounts, PUID/PGID, or VPN netns
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
    virtualisation.oci-containers.containers.uptime-kuma = {
      image = cfg.image;
      autoStart = true;

      volumes = [
        "${cfg.dataDir}:/app/data"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];

      environment = {
        TZ = "America/Denver";
        UPTIME_KUMA_PORT = toString cfg.port;
      };

      extraOptions = [
        "--network=host"
        "--memory=512m"
        "--cpus=0.5"
      ];
    };

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    # Auth OFF, baked in: uptime-kuma.hwc.* is tailnet-only (Caddy vhost over
    # Tailscale), so the login page is pure friction — the tailnet IS the auth,
    # same trust model as every other .hwc.* internal UI. Kuma has no env-var
    # for this (its own docs point proxy users at the disableAuth setting in
    # the DB), so upsert it before every container start: survives rebuilds,
    # image updates, and volume recreation. Skips silently on a brand-new
    # empty volume (no kuma.db yet — Kuma's first boot creates it, and the
    # next unit start bakes the setting).
    systemd.services.podman-uptime-kuma.serviceConfig.ExecStartPre = [
      (pkgs.writeShellScript "uptime-kuma-disable-auth" ''
        db="${cfg.dataDir}/kuma.db"
        [ -f "$db" ] || exit 0
        ${pkgs.sqlite}/bin/sqlite3 "$db" \
          "INSERT INTO setting (key, value, type) VALUES ('disableAuth', 'true', 'general')
           ON CONFLICT(key) DO UPDATE SET value = 'true';" || true
      '')
    ];

    # Caddy reverse proxy route
    hwc.networking.shared.routes = [
      {
        name = "uptime-kuma";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.port > 0 && cfg.port < 65536;
        message = "Uptime Kuma port must be between 1 and 65535";
      }
    ];
  };
}
