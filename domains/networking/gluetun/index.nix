{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.networking.gluetun;
  inherit (lib) mkOption mkEnableOption types;

  # One tunnel = one instance. This was a singleton until 2026-08-20; it became
  # an attrset because slskd needs its OWN Proton tunnel. Proton forwards exactly
  # one port per WireGuard session and qBittorrent already holds the one on the
  # original tunnel, so "slskd is behind the VPN" and "slskd keeps its inbound
  # Soulseek port" are only simultaneously true with a second tunnel and key.
  instanceModule = { name, ... }: {
    options = {
      enable = mkEnableOption "gluetun tunnel instance '${name}'";

      image = mkOption {
        type = types.str;
        default = "qmcgaw/gluetun:latest";
        description = "Container image";
      };

      privateKeySecret = mkOption {
        type = types.str;
        description = ''
          Name of the agenix secret holding this tunnel's WireGuard private key
          (the attribute under config.age.secrets, not a path). Each instance
          needs its OWN key — Proton ties the forwarded port to the session, so
          two tunnels sharing a key get one port between them.
        '';
      };

      # VPN_SERVICE_PROVIDER=custom pins exactly ONE peer and can never fail
      # over. That is a known, accepted weakness: on 2026-08-18 19:20 the
      # then-current pin stopped answering handshakes, gluetun restarted the
      # tunnel 4,219 times in 24h against the same dead peer, and the stack was
      # down ~33h. Provider mode (VPN_SERVICE_PROVIDER=protonvpn) rotates on
      # failure and is the real fix; it is tracked separately because it needs
      # healthcheck tuning that has never been verified here. What covers the
      # weakness NOW is parts/scripts.nix: sustained failure escalates once and
      # reaches the morning briefing instead of retrying silently forever.
      wireguard = {
        publicKey = mkOption {
          type = types.str;
          description = "Peer public key of the pinned server";
        };
        endpointIp = mkOption {
          type = types.str;
          description = "Pinned server IP — must be a port-forward-capable Proton server";
        };
        endpointPort = mkOption {
          type = types.port;
          default = 51820;
          description = "WireGuard endpoint port";
        };
        addresses = mkOption {
          type = types.str;
          description = ''
            WIREGUARD_ADDRESSES for this key, copied verbatim from the Proton
            config. Proton assigns it per key; a guessed value produces a tunnel
            that handshakes and then carries nothing.
          '';
        };
        keepalive = mkOption {
          type = types.str;
          default = "25s";
          description = "WIREGUARD_PERSISTENT_KEEPALIVE_INTERVAL";
        };
        serverLabel = mkOption {
          type = types.str;
          default = "";
          description = ''
            Human label for the pinned server (e.g. "US-VA#1 (Ashburn)"), written
            into the generated env file. Documentation only — but the previous
            pin sat mislabelled in a hand-written comment for months, so it is an
            option next to the IP rather than prose that can drift from it.
          '';
        };
      };

      controlPort = mkOption {
        type = types.port;
        description = ''
          HOST port for gluetun's control server (container side is always 8000).
          Unique per instance: this is what port-sync and the health check query,
          and a collision would make one instance report on the other.
        '';
      };

      networkAlias = mkOption {
        type = types.str;
        default = name;
        description = ''
          media-network alias. Containers living in this netns are reachable from
          the media network at THIS name, not their own — they have no interface
          of their own.
        '';
      };

      ports = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Ports published on behalf of every container in this netns. A container
          using --network=container:<this> cannot publish its own, so its ports
          belong here.
        '';
      };

      dns = mkOption {
        type = types.str;
        default = "1.1.1.1";
        description = "DNS_ADDRESS inside the tunnel (DoT stays off — it timed out)";
      };

      portForwarding = {
        enable = mkEnableOption "NAT-PMP port forwarding on this tunnel";

        syncTo = mkOption {
          type = types.nullOr (types.enum [ "qbittorrent" "slskd" ]);
          default = null;
          description = ''
            Which client's listen port follows this tunnel's forwarded port.
            Closed vocabulary: every value has a sync implementation in
            parts/config.nix, so adding a client forces adding its mechanism
            instead of silently doing nothing.
          '';
        };

        checkInterval = mkOption {
          type = types.int;
          default = 60;
          description = "Seconds between port sync checks";
        };
      };

      healthCheck = {
        enable = mkEnableOption "VPN + port-forwarding health monitor with auto-restart";

        checkInterval = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds between health checks";
        };

        failuresBeforeRestart = mkOption {
          type = types.int;
          default = 3;
          description = "Consecutive failed checks before the first auto-restart";
        };

        escalateAfterRestarts = mkOption {
          type = types.int;
          default = 4;
          description = ''
            How many restarts may fail before the instance is declared `failed`
            and paged ONCE. With the backoff below that is ~4h of trying: long
            enough to ride out a provider blip, short enough that a dead peer
            cannot eat another 33-hour night unnoticed.
          '';
        };

        backoffSteps = mkOption {
          type = types.listOf types.int;
          default = [ 900 1800 3600 7200 14400 ];
          description = ''
            Minimum seconds between successive restart attempts; the last value
            is the cap. Bounded retry (Principle 13): the previous code restarted
            every 15 min forever — 96 attempts and 43 identical alerts in a day
            against a peer that was never coming back.
          '';
        };

        notifyUrl = mkOption {
          type = types.nullOr types.str;
          default = "http://127.0.0.1:11600";
          description = ''
            hwc-notify base URL for transition alerts (topic=monitoring →
            #hwc-alerts). null disables alerting; auto-restart is unaffected.
            Replaced the gotify alert channel (decommissioned 2026-07-06).
          '';
        };

      };
    };
  };

  enabledInstances = lib.filterAttrs (_: i: i.enable) cfg.instances;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.networking.gluetun = {
    stateRoot = mkOption {
      type = types.str;
      default = "/var/lib/hwc/gluetun";
      readOnly = true;
      description = ''
        Runtime state root. Each instance owns `<stateRoot>/<name>/`, holding the
        forwarded port, the health state machine, and the status.json the morning
        briefing reads. Declared once here because three separate producers
        (port-sync, the health check, the briefing) address the same files, and
        drift between them is silent. AUTO-MANAGED retention: a fixed set of
        small files per instance, rewritten in place — it does not grow.
      '';
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule instanceModule);
      default = {};
      description = "VPN tunnel instances, keyed by container name";
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {
    # VPN secrets are declared in domains/secrets/declarations/infrastructure.nix
    # and named per instance via privateKeySecret.

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = lib.optionals (enabledInstances != {}) ([
      {
        assertion = config.hwc.secrets.enable;
        message = "Gluetun requires hwc.secrets.enable = true for VPN credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Gluetun requires Podman as OCI container backend";
      }
      {
        assertion =
          let ports = lib.mapAttrsToList (_: i: i.controlPort) enabledInstances;
          in lib.length ports == lib.length (lib.unique ports);
        message = "Each enabled gluetun instance needs its own controlPort (host side)";
      }
      {
        assertion =
          let aliases = lib.mapAttrsToList (_: i: i.networkAlias) enabledInstances;
          in lib.length aliases == lib.length (lib.unique aliases);
        message = "Each enabled gluetun instance needs its own networkAlias on media-network";
      }
    ]
    ++ lib.mapAttrsToList (name: i: {
      assertion = config.age.secrets ? ${i.privateKeySecret};
      message = "gluetun instance '${name}' needs agenix secret '${i.privateKeySecret}' (declared in domains/secrets/declarations/infrastructure.nix)";
    }) enabledInstances
    ++ lib.mapAttrsToList (name: i: {
      assertion = !i.portForwarding.enable || i.wireguard.endpointIp != "";
      message = "gluetun instance '${name}' has port forwarding on but no pinned endpoint";
    }) enabledInstances);
  };
}
