# Infrastructure Container Helper
# For containers with special network modes, capabilities, devices, etc.
# Used by: gluetun, pihole (infrastructure containers)
# See mkContainer.nix for application containers (media apps, *arr services)
{ lib, pkgs }:

rec {
  # containerDefOf — the podman definition itself, with no systemd wiring.
  # Single producer for both entry points below; they differ only in how many
  # containers they wire, never in what a container IS.
  containerDefOf =
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

    # Systemd/firewall wiring is the caller's business, not the definition's;
    # accepted and ignored here so both entry points can pass one arg set.
    , ...
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
    in containerDef;

  # mkInfraContainer - Creates infrastructure container with full control over
  # network mode, capabilities, devices, and integrated systemd services
  mkInfraContainer =
    args@{ name
    , preStartScript ? null
    , preStartDeps ? []
    , postStartScript ? null
    , assertions ? []
    , firewallTcp ? []
    , firewallUdp ? []
    , systemdAfter ? []
    , systemdWants ? []
    , systemdRequires ? []
    , ...
    }:
    let
      containerDef = containerDefOf args;

      # Pre-start service name
      preStartServiceName = "${name}-setup";

      # Container service name (podman convention)
      containerServiceName = "podman-${name}";

    in lib.mkMerge [
      # Container definition
      {
        # HWC-EXCEPTION(Law 5): this IS the sanctioned infra-container helper
        # Justification: peer of mkContainer for infrastructure-shaped containers (gluetun etc.); the raw definition is the helper itself, same status as mkContainer
        # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
        # Revocable: yes
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

  # mkInfraContainers — the same thing for a SET of containers whose membership
  # comes from config (gluetun's tunnel instances).
  #
  # Why a second entry point instead of `mkMerge (map mkInfraContainer …)`: a
  # module's `config` may be a plain attrset, or an mkIf/mkMerge whose contents
  # do NOT depend on config. The module system calls pushDownProperties on
  # mkIf/mkMerge before config is fixed, so a merge list built by mapping over a
  # config-derived attrset is infinite recursion — which is exactly what the
  # first attempt at multi-instance gluetun hit. The fix is shape, not cleverness:
  # this returns a plain attrset whose top-level names are literals, so only the
  # VALUES depend on config, and those are forced later, safely.
  #
  #   specs :: attrset of container-name -> the same argument set mkInfraContainer
  #            takes (minus `name`, which is the key)
  #
  # Returns a module fragment; merge extra services into it at the caller with
  # lib.mkMerge on the systemd.services VALUE (not at the top level).
  mkInfraContainers = specs:
    let
      named = lib.mapAttrs (name: args: args // { inherit name; }) specs;

      setupServices = lib.concatMapAttrs (name: a:
        lib.optionalAttrs (a.preStartScript or null != null) {
          "${name}-setup" = {
            description = "Setup for ${name} container";
            before = [ "podman-${name}.service" ];
            wantedBy = [ "podman-${name}.service" ];
            wants = a.preStartDeps or [];
            after = a.preStartDeps or [];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = false;
            };
            script = a.preStartScript;
          };
        }) named;

      containerServices = lib.mapAttrs' (name: a:
        lib.nameValuePair "podman-${name}" (
          {
            after = (a.systemdAfter or [])
              ++ lib.optional (a.preStartScript or null != null) "${name}-setup.service";
            wants = a.systemdWants or [];
            requires = a.systemdRequires or [];
          }
          // lib.optionalAttrs (a.postStartScript or null != null) {
            postStart = a.postStartScript;
          }
        )) named;
    in
    {
      # HWC-EXCEPTION(Law 5): this IS the sanctioned infra-container helper
      # Justification: same status as mkInfraContainer above — the raw definition
      # lives in the helper. This entry point exists only because the singular
      # one cannot express a config-derived SET without infinite recursion.
      # Plan: permanent by design
      # Revocable: yes
      virtualisation.oci-containers.containers =
        lib.mapAttrs (_: a: containerDefOf a) named;

      systemd.services = setupServices // containerServices;

      networking.firewall = {
        allowedTCPPorts = lib.concatLists (lib.mapAttrsToList (_: a: a.firewallTcp or []) named);
        allowedUDPPorts = lib.concatLists (lib.mapAttrsToList (_: a: a.firewallUdp or []) named);
      };
    };
}
