{ lib, pkgs, config, ... }:
let
  enabled  = config.hwc.home.apps.aerc.enable or false;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config; };
  bindsPart = import ./parts/behavior.nix { inherit lib pkgs config; };
  sessPart  = import ./parts/session.nix  { inherit lib pkgs config; };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf enabled {
    home.packages = (cfgPart.packages or []) ++ (sessPart.packages or []);
    home.file     = (cfgPart.files "") // (bindsPart.files "") // {
      ".notmuch-config".source =
        config.lib.file.mkOutOfStoreSymlink
          "${config.home.homeDirectory}/.config/notmuch/default/config";
    };
    home.shellAliases = (sessPart.shellAliases or {});

    # Replace the old cp/chmod block with this:
    home.activation.aerc-accounts-finalize = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      SRC="$HOME/.config/aerc/accounts.conf.source"
      DST="$HOME/.config/aerc/accounts.conf"
    
      # ensure no stale file remains
      ${pkgs.coreutils}/bin/rm -f "$DST"
    
      # overwrite with correct perms
      ${pkgs.coreutils}/bin/install -Dm600 "$SRC" "$DST"
    '';
  };
}
