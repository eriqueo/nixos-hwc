{ config, lib, pkgs, osConfig ? {}, ...}:

let
  cfg = config.hwc.home.apps.slack-cli;

  # Rename binary from 'slack' to 'slack-term' to avoid collision with desktop client
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
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ slack-cli-wrapped ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}