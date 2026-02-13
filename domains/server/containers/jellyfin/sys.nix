{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.jellyfin;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyfin/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "jellyfin";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = "UTC";   # Static default - timezone detection deferred
      ports = [ "127.0.0.1:8096:8096" ];
      volumes = [ "${configPath}:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
  ]);
}
