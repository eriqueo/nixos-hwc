{ lib, ... }:
{
  options.hwc.home.apps.obsidian = {
    enable = lib.mkEnableOption "Obsidian note-taking app";
  };
}
