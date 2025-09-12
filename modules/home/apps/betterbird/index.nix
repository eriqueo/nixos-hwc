# Home app: Betterbird — no Thunderbird fallback
{ config, lib, pkgs, ... }:

let
  cfg = config.features.betterbird or { enable = false; };

  # Hard-require Betterbird in nixpkgs
  _ = lib.assertMsg (lib.hasAttr "betterbird" pkgs)
        "pkgs.betterbird not found in this nixpkgs. Add an overlay or switch channels.";

  # Universal domains
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };

  homeDir     = config.home.homeDirectory;
  profileBase = "${homeDir}/.thunderbird"; # Betterbird uses TB profile layout
in
{
  options.features.betterbird.enable =
    lib.mkEnableOption "Enable Betterbird (no Thunderbird fallback)";

  config = lib.mkIf cfg.enable {
    # Only Betterbird + any per-app extras from session.parts
    home.packages = [ pkgs.betterbird ] ++ (session.packages or []);

    # Optional env (from session) + a stable profile var
    home.sessionVariables =
      (session.env or {}) // { THUNDERBIRD_PROFILE = "default-release"; };

    # Optional user services for this app
    systemd.user.services = (session.services or { });

    # Files from behavior/appearance (each part may return a function or a set)
    home.file = lib.mkMerge [
      (if builtins.isFunction behavior.files
         then behavior.files profileBase else (behavior.files or {}))
      (if builtins.isFunction appearance.files
         then appearance.files profileBase else (appearance.files or {}))
    ];
  };
}
