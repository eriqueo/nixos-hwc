# domains/home/apps/claude-code/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.claude-code ];

    # Trust the self-signed cert from the Obsidian Local REST API plugin
    # so Claude Code's HTTP MCP transport can connect without validation errors.
    # Cert source: https://127.0.0.1:27124/obsidian-local-rest-api.crt
    home.sessionVariables.NODE_EXTRA_CA_CERTS = "/home/eric/.claude/certs/obsidian-local-rest-api.crt";
  };
}
