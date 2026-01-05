{ lib, pkgs, config, nixosApiVersion ? "unstable", ... }:
let
  enabled  = config.hwc.home.apps.aerc.enable or false;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config nixosApiVersion; };
  bindsPart = import ./parts/behavior.nix { inherit lib pkgs config; };
  sessPart  = import ./parts/session.nix  { inherit lib pkgs config; };
  sievePart = import ./parts/sieve.nix    { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    home.packages = (cfgPart.packages or []) ++ (sessPart.packages or []);
    home.file     = (cfgPart.files "") // (bindsPart.files "") // (sievePart.files "") // {
      ".notmuch-config".source =
        config.lib.file.mkOutOfStoreSymlink
          "${config.home.homeDirectory}/.config/notmuch/default/config";
    };
    home.shellAliases = (sessPart.shellAliases or {});

    # Replace the old cp/chmod block with this:
    home.activation.aerc-accounts-finalize =
      config.lib.dag.entryAfter [ "linkGeneration" ] ''
        set -euo pipefail
        SRC="$HOME/.config/aerc/accounts.conf.source"
        DST="$HOME/.config/aerc/accounts.conf"
    
        if [ ! -f "$SRC" ]; then
          echo "aerc finalize: '$SRC' missing; aborting." >&2
          exit 1
        fi
    
        # create regular file with strict perms (not a symlink)
        ${pkgs.coreutils}/bin/install -Dm600 "$SRC" "$DST"
      '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !enabled || (config.hwc.home.mail.accounts != {} && config.hwc.home.mail.accounts != null);
        message = "aerc requires at least one mail account configured via hwc.home.mail.accounts";
      }
    ];
  };
}
