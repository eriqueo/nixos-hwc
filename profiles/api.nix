# profiles/api.nix
#
# HWC System Status API Profile (Proof of Concept)
#
# This profile, when imported by a machine, generates a static JSON file
# containing the configured state of the system and serves it via a simple
# web server, effectively creating a read-only REST API.
#
# It demonstrates how a declarative NixOS configuration can be used to
# build not just the system itself, but also its own status API.
#
# USAGE (in a machine's config.nix):
#   imports = [ ... ../profiles/api.nix ];
#
# Then, after a rebuild, you can access the API:
#   curl http://localhost:8080/api/status

{ config, lib, pkgs, ... }:

let
  # ========================================================================
  # API DATA CURATION
  # ========================================================================
  # This is the heart of the API. We manually and explicitly curate which
  # configuration values are safe and useful to expose.
  #
  # This manual step is a critical security gate. We ONLY include high-level
  # status flags and metadata, NEVER secrets, keys, or sensitive paths.

  apiData = {
    # --- Metadata ---
    meta = {
      # The hostname of the machine serving the API.
      hostname = config.networking.hostName;
      # The NixOS version the system was built with.
      nixosStateVersion = config.system.stateVersion;
      # The timestamp of when this API data was generated (i.e., build time ).
      lastBuildTime = builtins.currentTime;
      lastBuildTimestamp = (lib.trivial.time.format (builtins.currentTime) "%Y-%m-%dT%H:%M:%SZ");
    };

    # --- System Services Domain ---
    # We mirror the structure of our domains for a clean, predictable API.
    system = {
      services = {
        # Data from the 'networking' module
        networking = {
          enabled = config.hwc.system.networking.enable;
          firewallLevel = config.hwc.system.networking.firewall.level;
          ssh = {
            enabled = config.hwc.system.networking.ssh.enable;
            port = config.hwc.system.networking.ssh.port;
          };
          tailscale = {
            enabled = config.hwc.system.networking.tailscale.enable;
          };
          samba = {
            enabled = config.hwc.system.networking.samba.enable;
            # We can even count the number of configured shares.
            shareCount = lib.length (lib.attrNames config.hwc.system.networking.samba.shares);
          };
        };

        # Data from the 'hardware' module
        hardware = {
          enabled = config.hwc.system.services.hardware.enable;
          audioEnabled = config.hwc.system.services.hardware.audio.enable;
          keyboardManagerEnabled = config.hwc.system.services.hardware.keyboard.enable;
          monitoringEnabled = config.hwc.system.services.hardware.monitoring.enable;
        };

        # Data from the 'session' module
        session = {
          enabled = config.hwc.system.services.session.enable;
          loginManager = {
            enabled = config.hwc.system.services.session.loginManager.enable;
            autoLoginUser = config.hwc.system.services.session.loginManager.autoLoginUser;
          };
          sudo = {
            enabled = config.hwc.system.services.session.sudo.enable;
            wheelNeedsPassword = config.hwc.system.services.session.sudo.wheelNeedsPassword;
          };
        };

        # Data from the 'backup' module
        backup = {
          enabled = config.hwc.system.services.backup.enable;
          monitoringEnabled = config.hwc.system.services.backup.monitoring.enable;
          protonDrive = {
            enabled = config.hwc.system.services.backup.protonDrive.enable;
            # Exposing the *method* of auth, not the auth itself.
            authenticationMethod = if config.hwc.system.services.backup.protonDrive.useSecret then "secret" else "interactive/manual";
          };
        };

        # Data from the 'shell' module
        shell = {
          enabled = config.hwc.system.services.shell.enable;
        };
      };
    };

    # --- Server Domain (Example) ---
    # This section would only populate if server modules were enabled.
    server = {
      # Example: Exposing the status of a Caddy web server workload.
      # caddy = {
      #   enabled = config.hwc.server.caddy.enable;
      #   domainCount = lib.length (lib.attrNames config.services.caddy.virtualHosts);
      # };
    };
  };

  # ========================================================================
  # JSON FILE GENERATION
  # ========================================================================
  # Using built-in Nix functions, we convert the curated 'apiData' structure
  # from above into a JSON string and write it to a static file in the Nix store.
  # This file is immutable and generated entirely at build time.

  apiJsonFile = pkgs.writeText "hwc-system-api.json" (builtins.toJSON apiData);

in
{
  # ========================================================================
  # API SERVICE IMPLEMENTATION
  # ========================================================================
  # Here, we configure a lightweight web server (Caddy) to serve the
  # static JSON file we just created. This is the runtime component.

  config = {
    services.caddy = {
      enable = true;
      # For this example, we open a local port. For a real server,
      # you would use a public domain and configure HTTPS.
      virtualHosts."localhost:8080" = {
        extraConfig = ''
          # Set a JSON content type header for API clients.
          @api header Accept application/json
          header @api Content-Type application/json

          # When a request comes to /api/status...
          handle_path /api/status {
            # ...simply respond with the contents of the pre-generated JSON file.
            # This is extremely fast and secure as it's just serving a static file.
            root * ${builtins.dirOf apiJsonFile}
            file_server {
              path hwc-system-api.json
            }
          }

          # A default response for other paths.
          handle {
            respond "HWC System API is running. Access it at /api/status" 200
          }
        '';
      };
    };

    # Ensure the firewall, if managed by our networking module, allows access
    # to this API endpoint.
    hwc.system.networking.firewall.extraTcpPorts = [ 8080 ];
  };
}
