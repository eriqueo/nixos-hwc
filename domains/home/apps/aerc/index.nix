{ lib, pkgs, config, osConfig ? {}, ...}:
let
  enabled  = config.hwc.home.apps.aerc.enable or false;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config; };
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