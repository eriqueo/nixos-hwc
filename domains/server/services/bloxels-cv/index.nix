# domains/server/services/bloxels-cv/index.nix
#
# Bloxels CV — systemd path-watcher + oneshot service for phone photos of the
# printed 13x13 Bloxels grid. Watches a drop directory via inotify; runs the
# bloxels-capture pipeline (ArUco detect -> rectify -> CIELAB classify); writes
# grid.json + debug.png next to the photo so Syncthing carries results back to
# the phone. Package comes from the bloxels-cv flake input.
#
# Namespace: hwc.server.services.bloxelsCv
{ config, lib, ... }:

let
  cfg = config.hwc.server.services.bloxelsCv;
in

{
  imports = [
    ./sys.nix
  ];

  # OPTIONS
  options.hwc.server.services.bloxelsCv = {
    enable = lib.mkEnableOption "Bloxels CV processor (photo of 13x13 grid -> grid.json via path watcher)";

    package = lib.mkOption {
      type = lib.types.package;
      description = "bloxels-capture package (from the bloxels-cv flake input)";
    };

    watchPath = lib.mkOption {
      type = lib.types.str;
      description = "Directory to watch for new grid photos (.jpg/.jpeg/.png), e.g. a subdir of the inbox-mobile Syncthing share";
    };
  };

  # IMPLEMENTATION — delegated to sys.nix; this block holds assertions only.

  # VALIDATION
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.watchPath != "";
        message = "hwc.server.services.bloxelsCv.watchPath must be set";
      }
    ];
  };
}
