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
    mpv.enable = true;
    qutebrowser.enable = true;
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

  # Tasks: Apple Reminders (VTODO) sync via todoman, riding the calendar
  # vdirsyncer config + timer above. The laptop wires mail per-machine (no mail
  # role), so tasks is enabled here rather than in profiles/mail/home.nix.
  hwc.mail.tasks = {
    enable = true;
    # The two VTODO (Reminders) collections in this iCloud account. The other
    # discovered collections are VEVENT calendars (Home/Calendar/Work/Family-cal)
    # and must be excluded or todoman breaks on the duplicate "Family" name.
    # Verified via supported-calendar-component-set PROPFIND (2026-06-11):
    collections = [
      "36BB690C-8948-4AB5-A0CB-C0596887C4E5"  # "Reminders"
      "D788714B-EA8C-44D1-A16F-ECF1A88ADCC6"  # "Family"
    ];
    # Phase C second backend: self-hosted Radicale (tasks.hwc.iheartwoodcraft.com)
    # with two-way list creation. Flip to true AFTER the server is deployed and
    # the radicale-htpasswd secret exists — runbook in
    # domains/server/services/radicale/README.md. Until then the pair would
    # error on every 15-min sync.
    radicale.enable = false;
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
    # Mail lives on the server (laptop mbsync is disabled); run aerc there.
    # `command aerc` still reaches the local binary if ever needed.
    aliases.aerc = "ssh -t server aerc";
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
