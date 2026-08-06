# profiles/base/home.nix — base role, Home Manager lane
#
# CLI-shared HM defaults for every machine (headless-safe, OS-agnostic).
# All set with mkDefault — machines can override any option.
#
# REPLACES: the CLI-shared portion of profiles/home-session.nix
# USED BY: every machine (see the machines table in flake.nix)

{ config, lib, pkgs, nixosApiVersion ? "unstable", ... }:

{
  imports = [
    ../../domains/home/index.nix
  ];

  home.stateVersion = "24.05";

  # Restart changed user units on switch (sd-switch diffs the unit set).
  # DELIBERATE: this reaches every machine — user units, including the
  # server's mail timers, restart when their definitions change.
  systemd.user.startServices = "sd-switch";

  hwc.home = {
    # Theme — palette applies headless too (shell/CLI colors)
    theme.palette = lib.mkDefault "hwc";

    # Shell Environment
    core.shell = {
      enable = lib.mkDefault true;
      modernUnix = lib.mkDefault true;
      git.enable = lib.mkDefault true;
      zsh = {
        enable = lib.mkDefault true;
        starship = lib.mkDefault true;
        autosuggestions = lib.mkDefault true;
        syntaxHighlighting = lib.mkDefault true;
      };
    };

    # Development Environment
    core.development.enable = lib.mkDefault true;

    # Declared git hooks — every host pins ~/.nixos to its tracked .githooks/
    core.repoHooks = {
      enable = lib.mkDefault true;
      repos = [ { path = "${config.home.homeDirectory}/.nixos"; } ];
    };

    # CLI apps
    apps = {
      gpg.enable = lib.mkDefault true;
      yazi.enable = lib.mkDefault true;
      herdr.enable = lib.mkDefault true;
      codex.enable = lib.mkDefault true;
      pi.enable = lib.mkDefault true;
      aider.enable = lib.mkDefault true;
      gemini-cli.enable = lib.mkDefault true;
    };
  };

  #======================================================================
  # HM 26.05 STATEVERSION-DEFAULT PINS
  #======================================================================
  # HM 26.05 flipped the defaults of these three options; because
  # home.stateVersion is 24.05 we still get the legacy value, and HM warns
  # on every eval until the option is explicitly defined. Pinning the legacy
  # values preserves current behavior, silences the warnings, and makes the
  # eventual stateVersion bump a no-op rather than a silent behavior change.
  #
  # The options do not exist in HM stable 25.11, so the block is guarded on
  # nixosApiVersion — unguarded it breaks eval for stable-lane machines
  # (stable-lane eval regression from commit fce96f45).
  #
  # HISTORY: `configType` and `setSessionVariables` were briefly absent from
  # the HM-as-module wiring path (setting them errored at module-merge —
  # removed 2026-05-31). The 2026-05 nixpkgs/HM bump restored them to module
  # mode, so they were pinned again in profiles/desktop/home.nix on
  # 2026-06-10. Moved here 2026-07-29: the warnings also fire on unstable
  # machines that carry no desktop role (gaming- and appliance-only role
  # sets), and base is the only role every machine carries. Harmless on
  # machines with no graphical session — the
  # options are declared unconditionally by HM, and nothing is generated
  # unless the corresponding program is enabled.
  #
  # mkDefault is enough to silence the warning: HM attaches it to the option
  # *default* via lib.warn, so any definition at any priority stops it being
  # forced.
} // lib.optionalAttrs (nixosApiVersion == "unstable") {
  gtk.gtk4.theme = lib.mkDefault config.gtk.theme;
  wayland.windowManager.hyprland.configType = lib.mkDefault "hyprlang";
  xdg.userDirs.setSessionVariables = lib.mkDefault true;
}
