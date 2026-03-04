# Infrastructure Container Helper
# For containers with special network modes, capabilities, devices, etc.
# Used by: gluetun, pihole (infrastructure containers)
# See mkContainer.nix for application containers (media apps, *arr services)
{ lib, pkgs }:

rec {
  # mkInfraContainer - Creates infrastructure container with full control over
  # network mode, capabilities, devices, and integrated systemd services
  mkInfraContainer =
    { name                    # Container name
    , image                   # OCI image

    # Network (expanded options vs mkContainer)
    , networkMode ? "bridge"  # "bridge" | "host" | "container:<name>" | "none" | "media-network"
    , networkAliases ? []     # --network-alias for each
    , dnsServers ? []         # --dns for each

    # Capabilities & privileges
    , capabilities ? []       # NET_ADMIN, SYS_MODULE, etc.
    , devices ? []            # /dev/net/tun, etc. (format: "host:container" or just "path")
    , privileged ? false      # --privileged flag

    # Standard container options
    , ports ? []
    , volumes ? []
    , environment ? {}
    , environmentFiles ? []
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    , cmd ? []

    # Resource limits
    , memory ? "2g"
    , cpus ? "1.0"
    , memorySwap ? "4g"

    # Infrastructure-specific
    , preStartScript ? null   # Script to run before container (generates env files, etc.)
    , preStartDeps ? []       # Systemd services to wait for (e.g., "agenix.service")
    , postStartScript ? null  # Script to run after container starts
    , assertions ? []         # Pass-through assertions
    , firewallTcp ? []        # Open TCP ports
    , firewallUdp ? []        # Open UDP ports
    , systemdAfter ? []       # Additional systemd after deps
    , systemdWants ? []       # Additional systemd wants deps
    , systemdRequires ? []    # Additional systemd requires deps
    }:
    let
      # Build network options
      networkOpts =
        if networkMode == "host" then [ "--network=host" ]
        else if networkMode == "none" then [ "--network=none" ]
        else if networkMode == "media-network" then [ "--network=media-network" ]
        else if lib.hasPrefix "container:" networkMode then [ "--network=${networkMode}" ]
        else [ "--network=${networkMode}" ];  # bridge or custom

      # Network aliases (only valid for non-host networks)
      aliasOpts =
        if networkMode != "host" && networkAliases != []
        then map (a: "--network-alias=${a}") networkAliases
        else [];

      # DNS options
      dnsOpts = map (d: "--dns=${d}") dnsServers;

      # Capability options
      capOpts = map (c: "--cap-add=${c}") capabilities;

      # Device options
      deviceOpts = map (d: "--device=${d}") devices;

      # Privileged option
      privOpt = lib.optional privileged "--privileged";

      # Resource limits
      resourceOpts = [
        "--memory=${memory}"
        "--cpus=${cpus}"
        "--memory-swap=${memorySwap}"
      ];

      # Pre-start service name
      preStartServiceName = "${name}-setup";

      # Container service name (podman convention)
      containerServiceName = "podman-${name}";

      # Build container definition
      containerDef = {
        inherit image dependsOn;
        autoStart = true;
        environment = environment;
        environmentFiles = environmentFiles;
        extraOptions = networkOpts ++ aliasOpts ++ dnsOpts ++ capOpts
          ++ deviceOpts ++ privOpt ++ resourceOpts ++ extraOptions;
        ports = ports;
        volumes = volumes;
      } // lib.optionalAttrs (user != null) { inherit user; }
        // lib.optionalAttrs (cmd != []) { inherit cmd; };

    in lib.mkMerge [
      # Container definition
      {
        virtualisation.oci-containers.containers.${name} = containerDef;
      }

      # Pre-start systemd service (if script provided)
      (lib.mkIf (preStartScript != null) {
        systemd.services.${preStartServiceName} = {
          description = "Setup for ${name} container";
          before = [ "${containerServiceName}.service" ];
          wantedBy = [ "${containerServiceName}.service" ];
          wants = preStartDeps;
          after = preStartDeps;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
          };
          script = preStartScript;
        };
      })

      # Systemd service dependencies
      (lib.mkIf (systemdAfter != [] || systemdWants != [] || systemdRequires != [] || preStartScript != null) {
        systemd.services.${containerServiceName} = {
          after = systemdAfter
            ++ lib.optional (preStartScript != null) "${preStartServiceName}.service";
          wants = systemdWants;
          requires = systemdRequires;
        };
      })

      # Post-start script (if provided)
      (lib.mkIf (postStartScript != null) {
        systemd.services.${containerServiceName} = {
          postStart = postStartScript;
        };
      })

      # Firewall rules
      (lib.mkIf (firewallTcp != [] || firewallUdp != []) {
        networking.firewall = {
          allowedTCPPorts = firewallTcp;
          allowedUDPPorts = firewallUdp;
        };
      })

      # Pass-through assertions
      (lib.mkIf (assertions != []) {
        inherit assertions;
      })
    ];
}
