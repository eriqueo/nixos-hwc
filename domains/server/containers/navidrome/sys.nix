{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.navidrome;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "navidrome";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = "UTC";   # Static default - timezone detection deferred
      ports = [];
      volumes = [
        "/opt/downloads/navidrome:/config"
        "${config.hwc.paths.media}/music:/music:ro"  # Music library for streaming
      ];
      environment = {
        ND_BASEURL = "/music";  # Required for Caddy subpath routing
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
  ]);
}
