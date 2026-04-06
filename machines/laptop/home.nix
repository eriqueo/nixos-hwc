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
      calcurse.enable = true;
      calcure.enable = true;
      imv.enable = true;
      qbittorrent.enable = true;
      aider.enable = true;
      claude-code.enable = true;
      claude-desktop.enable = true;
      scraper.enable = true;
    };

    # Calendar: Apple iCloud sync via khal + vdirsyncer (CalDAV)
    hwc.mail.calendar = {
      enable = true;
      accounts = {
        icloud = {
          email = "eric@iheartwoodcraft.com";
          color = "dark green";
        };
      };
    };
    hwc.mail.health = {
      enable = false;

    };
    # eXoDOS launcher desktop entry
    xdg.desktopEntries.exogui = {
      name = "eXoDOS";
      comment = "DOS Game Collection Browser";
      exec = "bash /home/eric/eXoDOS/exogui.command";
      icon = "/home/eric/eXoDOS/eXo/util/exodos.png";
      categories = [ "Game" ];
    };

    # Shell: MCP configured for laptop context
    hwc.home.shell = {
      enable = true;
      mcp = {
        enable = true;
        includeConfigDir = false;   # don't expose ~/.config to Claude
        includeServerTools = false; # no server MCP tools on laptop
        n8n = {
          enable = true;
          # accessToken is set via agenix secret injection or overridden locally.
          # To set temporarily: add  accessToken = "your-token-here";  below.
          # Long-term: wire this through an activation script reading the agenix secret file.
          accessToken = ""; # REPLACE with your token or wire via agenix
        };
      };
    };

  };
}
