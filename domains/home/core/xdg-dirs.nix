# domains/home/core/xdg-dirs.nix
#
# XDG User Directories Auto-Update
# Ensures ~/.config/user-dirs.dirs stays in sync with system defaults
{ config, lib, pkgs, ... }:

{
  config = {
    # Automatically update XDG user directories on activation
    # This reads /etc/xdg/user-dirs.defaults and writes ~/.config/user-dirs.dirs
    home.activation.updateXdgDirs = config.lib.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update
    '';
  };
}
