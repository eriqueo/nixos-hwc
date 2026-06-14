# domains/home/apps/claude-desktop/index.nix
#
# Claude Desktop GUI (Electron) — Cowork-capable Linux port
# Provides chat, code, and full Cowork (Local Agent Mode) support.
# Source: github:johnzfitch/claude-cowork-linux (flake input `claude-cowork`,
# exposed as pkgs.claude-cowork-linux via overlay in flake.nix). This port runs
# Claude Code directly under bubblewrap (no VM/FHS wrapper); the package bundles
# its own runtime deps (electron_41, bubblewrap, curl, zstd, dbus, …) on PATH.
# MCP config at ~/.config/Claude/claude_desktop_config.json is untouched.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-desktop;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop GUI (Cowork-capable Linux port)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.claude-cowork-linux
    ];
  };
}
