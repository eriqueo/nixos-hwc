# domains/home/apps/neomutt/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.neomutt;

  mailAccs = config.hwc.home.mail.accounts or {};
  vals     = lib.attrValues mailAccs;
  haveAccs = vals != [];

  primary =
    let chosen = let p = lib.filter (a: a.primary or false) vals;
                 in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);
    in chosen;

  on = cfg.enable && haveAccs;

  theme      = import ./parts/theme.nix      { inherit config lib; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config theme; };
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };
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
        "hwc.home.apps.neomutt.enable = true but no hwc.home.mail.accounts are defined; disabling NeoMutt to avoid a bad config."
      ];
    })

    # Normal configuration path
    (lib.mkIf on {
      # If your parts need to know the chosen account, you can expose it like this:
      # (purely internal; optional)
      _module.args.hwcNeomuttPrimary = primary;

      home.packages         = (session.packages or []);
      home.sessionVariables = (session.env or {});
      systemd.user.services = (session.services or {});

      home.file = lib.mkMerge [
        (appearance.files config.home.homeDirectory)
        (behavior.files   config.home.homeDirectory)
      ];
    })
  ];
}