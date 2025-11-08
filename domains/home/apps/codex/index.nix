# domains/home/apps/codex/index.nix
#
# OpenAI Codex CLI for user environment - Home Manager implementation
{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.hwc.home.apps.codex;
  codexPkg = if cfg.package != null then cfg.package else
    inputs.codex.packages.${pkgs.system}.default;
in
{
  imports = [ ./options.nix ];

  config = mkIf cfg.enable {
    home.packages = [ codexPkg ];

    home.sessionVariables = cfg.env;

    # Create config directory
    xdg.configFile."codex/.keep".text = "";
  };
}
