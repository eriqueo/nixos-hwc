# domains/networking/pihole/sys.nix
{ lib, config, pkgs, ... }:
let
  # Import infrastructure container helper
  infraHelpers = import ../../../lib/mkInfraContainer.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainer;

  cfg = config.hwc.networking.pihole;
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

    # Pi-hole OCI Container using mkInfraContainer
    (mkInfraContainer {
      name = "pihole";
      image = cfg.image;

      # Network configuration - host mode for DNS
      networkMode = "host";

      # Infrastructure capabilities
      capabilities = [ "NET_ADMIN" ];
      dnsServers = [ "127.0.0.1" "1.1.1.1" ];

      # Ports (needed for firewall even in host mode)
      ports = [
        "${toString cfg.dnsPort}:53/tcp"
        "${toString cfg.dnsPort}:53/udp"
        "${toString cfg.webPort}:80/tcp"
      ];

      # Volume mounts
      volumes = [
        "${cfg.dataDir}:/etc/pihole"
        "${cfg.dnsmasqDir}:/etc/dnsmasq.d"
      ];

      # Environment from agenix-generated file (if using secrets)
      environmentFiles = lib.optional (cfg.webPasswordFile != null) "${cfg.dataDir}/.env";

      # Static environment
      environment = {
        TZ = cfg.timezone;
        PIHOLE_DNS_ = upstreamDnsString;
        DNSMASQ_LISTENING = "all";
        WEB_PORT = toString cfg.webPort;
        IPv6 = "true";
        QUERY_LOGGING = "true";
        FTLCONF_LOCAL_IPV4 = "0.0.0.0";
      } // cfg.extraEnvironment
        // lib.optionalAttrs (cfg.webPasswordFile == null && cfg.webPassword != "") {
          WEBPASSWORD = cfg.webPassword;
        };

      # Pre-start script to generate env file from agenix secrets
      preStartScript = lib.optionalString (cfg.webPasswordFile != null) ''
        mkdir -p ${cfg.dataDir}
        WEBPASSWORD=$(cat ${cfg.webPasswordFile})
        cat > ${cfg.dataDir}/.env <<EOF
WEBPASSWORD=$WEBPASSWORD
EOF
        chmod 600 ${cfg.dataDir}/.env
      '';
      preStartDeps = lib.optionals (cfg.webPasswordFile != null) [ "agenix.service" ];

      # Firewall rules
      firewallTcp = [ cfg.dnsPort cfg.webPort ];
      firewallUdp = [ cfg.dnsPort ];

      # Assertions
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
    })
  ]);
}
