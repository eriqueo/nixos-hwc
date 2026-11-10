# domains/home/apps/neomutt/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.neomutt;

  mailAccs = config.hwc.mail.accounts or {};
  accounts = lib.attrValues mailAccs;
  haveAccs = accounts != [];

  primary =
    lib.findFirst (a: a.primary or false) (if haveAccs then lib.head accounts else null) accounts;

  on = cfg.enable && haveAccs;

  theme      = import ./parts/theme.nix {};
  appearance = import ./parts/appearance.nix { inherit lib accounts primary theme; };
  behavior   = import ./parts/behavior.nix   { inherit lib accounts; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.neomutt = {
    enable = lib.mkEnableOption "NeoMutt email client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    # Warn (once) if the app is enabled but there are no accounts to bind to
    (lib.mkIf (cfg.enable && !haveAccs) {
      warnings = [
        "hwc.home.apps.neomutt.enable = true but no hwc.mail.accounts are defined; disabling NeoMutt to avoid a bad config."
      ];
    })

    # Normal configuration path
    (lib.mkIf on {
      home.packages = with pkgs; [
        neomutt msmtp isync notmuch urlscan abook lynx zathura
      ];

      home.file = lib.mkMerge [
        appearance.files
        behavior.files
      ];
    })
  ];
}