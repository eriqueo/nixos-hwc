# machines/laptop/home.nix
#
# MACHINE: HWC-LAPTOP — Home Manager overrides
# Machine-specific HM option overrides. Profiles/home.nix provides defaults;
# this file adjusts only what is unique to this machine.

{ lib, ... }:

{
  home-manager.users.eric = {

    # Apps enabled on this machine specifically
    hwc.home.apps = {
      imv.enable = true;
      qbittorrent.enable = true;
      aider.enable = true;
    };

    # Shell: MCP configured for laptop context
    hwc.home.shell = {
      enable = true;
      mcp = {
        enable = true;
        includeConfigDir = false;   # don't expose ~/.config to Claude
        includeServerTools = false; # no server MCP tools on laptop
      };
    };

  };
}
