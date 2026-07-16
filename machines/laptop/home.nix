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
    # Zero-touch receive: pull server-side ~/.claude-config edits every 15 min.
    claude-code.shareConfig.autoPull.enable = true;
    claude-desktop.enable = true;
    scraper.enable = true;
    markitdown.enable = true;
    dt.enable = true;
    dxlog.enable = true;
    gpu-screen-recorder.enable = true;  # gsr-toggle / SHIFT+PRINT call recording
    whisper-cpp = {
      enable = true;
      cuda = true;
      models = [ "medium.en" "large-v3" ];
    };

    # The MCP gateway runs on hwc-server (localhost:6200 there), not the laptop.
    # Reach it over the tailnet; without this workbench points at a dead local
    # 127.0.0.1:6200 and silently falls back to fixtures. (enable: desktop role.)
    workbench.gatewayUrl = "http://hwc-server:6200";
  };

  # Calendar: self-hosted Radicale (CalDAV) via khalt's khal + vdirsyncer,
  # plumbed exactly like tasks below. iCloud retired 2026-06-15 — calendar
  # data was migrated to Radicale (one-time import, see
  # domains/mail/calendar/README.md "Migration"); the old iCloud vdir at
  # ~/.local/share/vdirsyncer/calendars/icloud/ stays on disk as the import
  # source until verified, then can be archived. With radicale.enable on, the
  # iCloud account pairs are no longer generated.
  hwc.mail.calendar = {
    enable = true;
    icsWatch.enable = false;
    radicale.enable = true;
  };

  # CardDAV rolodex (khard + aerc completion) against the CRM-owned
  # eric/contacts address book — bidirectional peer of the iPhone account.
  hwc.mail.contacts.enable = true;

  # Tasks: VTODO sync via todoman/todui, riding the calendar vdirsyncer
  # config + timer above. The laptop wires mail per-machine (no mail role),
  # so tasks is enabled here rather than in profiles/mail/home.nix.
  hwc.mail.tasks = {
    enable = true;
    # iCloud pair DEAD as of 2026-06-11: Apple's Reminders "upgrade" was
    # triggered phone-side and permanently removed CalDAV access to iCloud
    # reminders (collections now serve only "The creator of this list has
    # upgraded these reminders." placeholders; old pinned collections were
    # deleted server-side). Irreversible — do not re-enable. Local task data
    # was migrated to Radicale; old vdir archived at
    # ~/.local/share/vdirsyncer/archive-icloud-tasks-2026-06-11/ (named to
    # stay outside todoman's tasks*/* glob).
    icloud.enable = false;
    # Primary backend: self-hosted Radicale (tasks.hwc.iheartwoodcraft.com)
    # with two-way list creation (todui `N`). Server deployed + secret
    # provisioned 2026-06-11; runbook in domains/server/services/radicale/README.md.
    radicale.enable = true;
  };

  hwc.mail.mbsync.enable = false;

  hwc.mail.health = {
    enable = false;
  };

  # eXoDOS (flatpak auto-install + launcher) — domains/home/apps/exodos
  hwc.home.apps.exodos.enable = true;

  # Route Electron/libsecret keyring (Claude Desktop OAuth tokens, etc.) through
  # pass instead of the weak --password-store=basic. Root / is unencrypted here,
  # so basic = tokens ~plaintext on disk; pass keeps them GPG-encrypted. gpg is
  # already enabled via profiles/base; Claude Desktop's launcher auto-detects
  # org.freedesktop.secrets and upgrades off basic on its own.
  hwc.home.apps.gpg.secretService.enable = true;

  # Shell: MCP configured for laptop context
  hwc.home.core.shell = {
    enable = true;
    # Mail lives on the server (laptop mbsync is disabled); run aerc there.
    # `command aerc` still reaches the local binary if ever needed.
    aliases.aerc = "ssh -t server aerc";
    # datax/jt-mcp relocated to a worktree-container layout (2026-06-26): the repo
    # root is now a container holding main/ (read-only upstream mirror) + eok/* work
    # worktrees. Point the jump aliases at main/. Laptop-only override — the server's
    # checkouts are not relocated, so its base cdd/cdj (parts/aliases.nix) stay as-is.
    aliases.cdd = "cd ~/700_datax/datax/main";
    aliases.cdj = "cd ~/700_datax/jt-mcp/main";
    mcp = {
      enable = true;
      includeConfigDir = false;   # don't expose ~/.config to Claude
      includeServerTools = false; # no server MCP tools on laptop
      brain.enable = true;        # vault CRUD + semantic search over the tailnet (brain-mcp :23443)
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
