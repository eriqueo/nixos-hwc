# domains/server/containers/pihole/sys.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.pihole;
  upstreamDnsString = lib.concatStringsSep ";" cfg.upstreamDns;
in
{
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Create data directories
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
        "d ${cfg.dnsmasqDir} 0755 root root -"
      ];
    }

    # Generate environment file from secrets at runtime (CHARTER-compliant: no builtins.readFile)
    (lib.mkIf (cfg.webPasswordFile != null) {
      systemd.services.pihole-env-setup = {
        description = "Generate Pi-hole environment file from agenix secrets";
        before = [ "podman-pihole.service" ];
        wantedBy = [ "podman-pihole.service" ];
        wants = [ "agenix.service" ];
        after = [ "agenix.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p ${cfg.dataDir}
          WEBPASSWORD=$(cat ${cfg.webPasswordFile})
          cat > ${cfg.dataDir}/.env <<EOF
WEBPASSWORD=$WEBPASSWORD
EOF
          chmod 600 ${cfg.dataDir}/.env
        '';
      };
    })

    # Disable systemd-resolved DNS stub listener if requested
    (lib.mkIf cfg.disableResolvedStub {
      services.resolved = {
        extraConfig = ''
          DNSStubListener=no
        '';
      };
      # Also configure the system to use Pi-hole for DNS
      networking.nameservers = [ "127.0.0.1" ];
    })

    # Pi-hole OCI Container
    {
      virtualisation.oci-containers.containers.pihole = {
        image = cfg.image;
        autoStart = true;

        ports = [
          "${toString cfg.dnsPort}:53/tcp"
          "${toString cfg.dnsPort}:53/udp"
          "${toString cfg.webPort}:80/tcp"
        ];

        volumes = [
          "${cfg.dataDir}:/etc/pihole"
          "${cfg.dnsmasqDir}:/etc/dnsmasq.d"
        ];

        # Use environmentFiles for secrets (CHARTER-compliant: no Nix store leaks)
        environmentFiles = lib.optional (cfg.webPasswordFile != null) "${cfg.dataDir}/.env";

        environment = {
          TZ = cfg.timezone;
          # WEBPASSWORD from environmentFiles if using secrets, otherwise from option
          PIHOLE_DNS_ = upstreamDnsString;
          DNSMASQ_LISTENING = "all";
          WEB_PORT = toString cfg.webPort;
          # Enable IPv6 support
          IPv6 = "true";
          # Query logging for statistics
          QUERY_LOGGING = "true";
          # FTL options
          FTLCONF_LOCAL_IPV4 = "0.0.0.0";
        } // cfg.extraEnvironment
          // lib.optionalAttrs (cfg.webPasswordFile == null && cfg.webPassword != "") {
            # Only set WEBPASSWORD directly if not using file
            WEBPASSWORD = cfg.webPassword;
          };

        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--dns=127.0.0.1"
          "--dns=1.1.1.1"
          "--network=host"
        ];
      };
    }

    # Firewall Configuration
    {
      networking.firewall = {
        allowedTCPPorts = [ cfg.dnsPort cfg.webPort ];
        allowedUDPPorts = [ cfg.dnsPort ];
      };
    }

    # Service dependencies (ensure agenix runs before container)
    (lib.mkIf (cfg.webPasswordFile != null) {
      systemd.services."podman-pihole" = {
        after = [ "agenix.service" "pihole-env-setup.service" ];
        wants = [ "agenix.service" ];
      };
    })

    #==========================================================================
    # VALIDATION
    #==========================================================================
    {
      assertions = [
        {
          assertion = !cfg.enable || config.virtualisation.oci-containers.backend == "podman";
          message = "Pi-hole requires Podman to be configured as the OCI container backend.";
        }
        {
          assertion = !cfg.enable || config.hwc.system.networking.enable;
          message = "Pi-hole requires hwc.system.networking.enable = true for firewall configuration.";
        }
        {
          assertion = !cfg.enable || (cfg.dnsPort != 53 || cfg.disableResolvedStub);
          message = ''
            Pi-hole is configured to use port 53, but systemd-resolved is using it.
            Either set disableResolvedStub = true (recommended) or use a different dnsPort.
          '';
        }
        {
          assertion = !cfg.enable || (cfg.webPassword != "" || cfg.webPasswordFile != null);
          message = ''
            Pi-hole requires either webPassword or webPasswordFile to be set.
            For production, use webPasswordFile with agenix secrets.
          '';
        }
        {
          assertion = !cfg.enable || (cfg.upstreamDns != []);
          message = "Pi-hole requires at least one upstream DNS server in upstreamDns.";
        }
      ];
    }
  ]);
}
