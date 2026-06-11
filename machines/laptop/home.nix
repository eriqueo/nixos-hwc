# machines/laptop/home.nix
#
# MACHINE: HWC-LAPTOP — Home Manager overrides
# Machine-specific HM option overrides. Profiles/home-session.nix provides defaults;
# this file adjusts only what is unique to this machine.
# Shared between NixOS module (nixos-rebuild) and standalone (home-manager switch).

{ lib, pkgs, ... }:

{
  # Codex pinned to the upstream release binary (faster-moving than the
  # unstable channel). Server intentionally stays on stock pkgs.codex.
  hwc.home.apps.codex.package =
    pkgs.callPackage ../../domains/home/apps/codex/parts/package.nix { };

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
    markitdown.enable = true;
    dt.enable = true;
    dxlog.enable = true;
    whisper-cpp = {
      enable = true;
      cuda = true;
      models = [ "medium.en" "large-v3" ];
    };
  };

  # Calendar: Apple iCloud sync via khal + vdirsyncer (CalDAV)
  hwc.mail.calendar = {
    enable = true;
    icsWatch.enable = false;
    accounts = {
      icloud = {
        email = "eric@iheartwoodcraft.com";
        color = "dark green";
      };
    };
  };
  hwc.mail.mbsync.enable = false;

  hwc.mail.health = {
    enable = false;
  };

  # eXoDOS (flatpak auto-install + launcher) — domains/home/apps/exodos
  hwc.home.apps.exodos.enable = true;

  # Shell: MCP configured for laptop context
  hwc.home.core.shell = {
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
}
