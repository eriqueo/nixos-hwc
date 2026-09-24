# machines/laptop/home.nix
#
# MACHINE: HWC-LAPTOP — Home Manager overrides
# Machine-specific HM option overrides. Profiles/home-session.nix provides defaults;
# this file adjusts only what is unique to this machine.
# Shared between NixOS module (nixos-rebuild) and standalone (home-manager switch).

{ config, lib, pkgs, ... }:
let dictationModel = "base.en"; in

{
  # Codex pinned to the upstream release binary (faster-moving than the
  # unstable channel). Server intentionally stays on stock pkgs.codex.
  hwc.home.apps.codex.package =
    pkgs.callPackage ../../domains/home/apps/codex/parts/package.nix { };

  # Blender pinned to the official upstream binary. pkgs.blender.override
  # { cudaSupport = true; } is a variant Hydra never builds, so the default path
  # recompiles blender + its CUDA-context deps (~30 min) on every nixpkgs bump.
  # The upstream tarball bundles those deps and ships the CUDA/OptiX Cycles
  # kernels — verified enumerating this laptop's RTX 2000 Ada on both backends.
  hwc.home.apps.blender.package =
    pkgs.callPackage ../../domains/home/apps/blender/parts/package.nix { };

  # Apps enabled on this machine specifically
  hwc.home.apps = {
    calcurse.enable = true;
    calcure.enable = true;
    imv.enable = true;
    mpv.enable = true;
    qutebrowser.enable = true;
    vesktop.enable = true;
    qbittorrent.enable = true;
    aider.enable = true;
    # shareConfig (and its two-way sync) defaults on with the package.
    claude-code.enable = true;
    claude-desktop.enable = true;
    # This machine's own tailnet address, pinned so the phone's endpoint does not
    # depend on whether tailscale0 had an address when the app started. See the
    # option's description — the desktop app resolves exposure once at bootstrap
    # and silently falls back to loopback when that one read comes up empty.
    t3code.desktop.lanHost = "100.71.213.18";
    scraper.enable = true;
    markitdown.enable = true;
    dt.enable = true;
    dxlog.enable = true;
    doctl.enable = true;
    # `brain <cmd>` — the vault janitor/fixer CLI. Not in the base role: it needs the
    # ~/600_apps/brain checkout and the vault, which only laptop + server carry.
    brain.enable = true;
    gpu-screen-recorder.enable = true;  # gsr-toggle / SHIFT+PRINT call recording
    hwc-dictation = {
      enable = true;
      model = "${config.hwc.home.apps.whisper-cpp.modelsDir}/ggml-${dictationModel}.bin";
    };
    waybar.powerHub.enable = true;
    whisper-cpp = {
      enable = true;
      cuda = true;
      models = [ dictationModel "medium.en" "large-v3" ];
    };

    # The MCP gateway runs on hwc-server (localhost:6200 there), not the laptop.
    # Reach it over the tailnet; without this workbench points at a dead local
    # 127.0.0.1:6200 and silently falls back to fixtures. (enable: desktop role.)
    workbench.gatewayUrl = "http://hwc-server:6200";
  };

  # Calendar: self-hosted Radicale (CalDAV) via khalt's khal + vdirsyncer,
  # plumbed exactly like tasks below. iCloud retired 2026-06-15 and its code
  # path was deleted 2026-09-24; Radicale is the only backend.
  hwc.mail.calendar = {
    enable = true;
    icsWatch.enable = false;
    # Read-only mirrors the server keeps in Radicale
    # (machines/server/config.nix hwc.server.services.radicale.mirrors).
    radicale.extraCollections = [ "cto" "proton-work" "google-family" ];
  };

  # CardDAV rolodex (khard + aerc completion) against the CRM-owned
  # eric/contacts address book — bidirectional peer of the iPhone account.
  hwc.mail.contacts.enable = true;

  # Tasks: VTODO sync via todoman/todui, riding the calendar vdirsyncer
  # config + timer above. The laptop wires mail per-machine (no mail role),
  # so tasks is enabled here rather than in profiles/mail/home.nix.
  # Backend: self-hosted Radicale (tasks.hwc.iheartwoodcraft.com) with two-way
  # list creation (todui `N`); runbook in domains/server/services/radicale/README.md.
  hwc.mail.tasks.enable = true;

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
