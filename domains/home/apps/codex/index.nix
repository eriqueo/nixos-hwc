# domains/home/apps/codex/index.nix
#
# OpenAI Codex CLI for user environment - Home Manager implementation
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.codex;
  enabled = cfg.enable or false;

  # Use package from config if specified, otherwise use nixpkgs
  codexPkg = if cfg.package != null then cfg.package else pkgs.codex;
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
    home.packages = [ codexPkg ];

    home.sessionVariables = cfg.env;

    # Create config directory
    xdg.configFile."codex/.keep".text = "";

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = codexPkg != null;
        message = "codex package must be available";
      }
    ];
  };
}
