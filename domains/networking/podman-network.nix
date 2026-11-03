{ lib, config, pkgs, ... }:
let
  helpers = import ../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mediaNetworkName;
  podman = "${pkgs.podman}/bin/podman";
  internal = config.hwc.networking.internalContainerNetworks;
in
{
  assertions = [{
    assertion = builtins.length internal == builtins.length (lib.unique internal)
      && !(builtins.elem mediaNetworkName internal);
    message = "Internal Podman bridges must be unique and separate from media-network";
  }];
  # REPLACEABLE: one bridge per declared name. Retire a declaration only after
  # its containers are detached, then remove that exact unused bridge.
  systemd.services = lib.listToAttrs (map (name: {
    name = lib.removeSuffix ".service" (helpers.internalNetworkUnit name);
    value = {
      description = "Create and validate internal Podman bridge ${name}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 30; };
      script = ''
        exec ${pkgs.python3}/bin/python3 - <<'PY'
        import json, subprocess
        command = [${builtins.toJSON podman}, 'network']
        name = ${builtins.toJSON name}
        present = subprocess.run(command + ['exists', name], capture_output=True)
        if present.returncode == 1:
            subprocess.run(command + ['create', '--internal', name], check=True, capture_output=True)
        elif present.returncode != 0:
            raise SystemExit('internal_network_inspection_failed')
        value = json.loads(subprocess.check_output(command + ['inspect', name]))[0]
        if not (value['internal'] is True and value['dns_enabled'] is True
                and value['ipv6_enabled'] is False and value['driver'] == 'bridge'):
            raise SystemExit('internal_network_policy_mismatch')
        print('Validated internal bridge ' + name)
        PY
      '';
    };
  }) internal) // { init-media-network = {
    description = "Create podman media network (idempotent)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      if ! ${podman} network exists ${mediaNetworkName}; then
        ${podman} network create ${mediaNetworkName}
      else
        echo "${mediaNetworkName} exists"
      fi
    '';
  }; };

  # Ensure the network is created by the time services start
  systemd.targets.multi-user.wants = [ "init-media-network.service" ];
}
