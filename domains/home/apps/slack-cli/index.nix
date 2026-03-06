# domains/home/apps/slack-cli/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.slack-cli;

  slack-cli-wrapped = pkgs.symlinkJoin {
    name = "slack-cli-wrapped";
    paths = [ pkgs.slack-cli ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/slack
      makeWrapper ${pkgs.slack-cli}/bin/slack $out/bin/slack-term
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.slack-cli = {
    enable = lib.mkEnableOption "Slack CLI (terminal client)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ slack-cli-wrapped ];
  };
}