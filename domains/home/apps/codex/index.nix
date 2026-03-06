# domains/home/apps/codex/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.codex;
  codexPkg = if cfg.package != null then cfg.package else (pkgs.codex or null);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.codex = {
    enable = lib.mkEnableOption "OpenAI Codex CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Codex package to use. If null, will use flake input.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for Codex CLI";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
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