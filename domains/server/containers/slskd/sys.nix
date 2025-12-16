{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.slskd;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using helper
    (helpers.mkContainer {
      name = "slskd";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;  # slskd doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [
        "0.0.0.0:5031:5030"        # Web UI
        "0.0.0.0:50300:50300/tcp"  # P2P port
      ];
      volumes = [
        "/mnt/hot/downloads/incomplete:/downloads/incomplete"
        "/mnt/hot/downloads/music:/downloads/music"
        "/mnt/media/music:/music:ro"
        "/etc/slskd/slskd.yml:/app/slskd.yml:ro"
      ];
      environment = {};
      cmd = [ "--config" "/app/slskd.yml" ];
    })

    # Firewall for P2P
    {
      networking.firewall.allowedTCPPorts = [ 50300 5031 ];
    }

    # Service dependencies
    {
      systemd.services."podman-slskd" = {
        after = [ "network-online.target" "init-media-network.service" "slskd-config-generator.service" "mnt-hot.mount" ];
        wants = [ "network-online.target" ];
        requires = [ "slskd-config-generator.service" "mnt-hot.mount" ];
      };
    }
  ]);
}
