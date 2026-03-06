# domains/home/apps/aerc/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.aerc;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config; };
  bindsPart = import ./parts/behavior.nix { inherit lib pkgs config; };
  sessPart  = import ./parts/session.nix  { inherit lib pkgs config; };
  sievePart = import ./parts/sieve.nix    { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.aerc = {
    enable = lib.mkEnableOption "aerc terminal email client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = (cfgPart.packages or []) ++ (sessPart.packages or []);
    home.file     = (cfgPart.files "") // (bindsPart.files "") // (sievePart.files "") // {
      ".notmuch-config".source =
        config.lib.file.mkOutOfStoreSymlink
          "${config.home.homeDirectory}/.config/notmuch/default/config";
    };
    home.shellAliases = (sessPart.shellAliases or {});

    home.activation.aercAccounts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Ensure aerc accounts.conf is a real file with restrictive perms
      install -m600 -D ${cfgPart.accountsFile} "$HOME/.config/aerc/accounts.conf"
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (config.hwc.home.mail.accounts != {} && config.hwc.home.mail.accounts != null);
        message = "aerc requires at least one mail account configured via hwc.home.mail.accounts";
      }
    ];
  };
}
