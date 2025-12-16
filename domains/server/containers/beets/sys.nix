{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.beets;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "beets";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:8337:8337" ];  # Beets web interface
      volumes = [
        "${cfg.configDir}:/config"
        "${cfg.musicDir}:/music"
        "${cfg.importDir}:/imports"
        "/mnt/media/quarantine:/quarantine"
      ];
      environment = {
        PUID = "1000";
        PGID = "100";
      };
      dependsOn = [ ];
    })
  ]);
}
