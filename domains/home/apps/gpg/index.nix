# domains/home/apps/gpg/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.gpg;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.gpg = {
    enable = lib.mkEnableOption "GPG and gpg-agent";

    # pass-secret-service exposes the existing pass store over the
    # org.freedesktop.secrets D-Bus API, so Electron/Chromium apps (Claude
    # Desktop, etc.) use pass (GPG-encrypted) as their keyring backend instead
    # of the weak `--password-store=basic` fallback. Opt-in per machine: only
    # graphical hosts with a D-Bus session want a SecretService daemon — a
    # headless server should leave this off.
    secretService.enable =
      lib.mkEnableOption "pass-secret-service (org.freedesktop.secrets over pass)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Enable GPG and the user gpg-agent service
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      # Use GUI pinentry for systemd services (Bridge, etc.)
      pinentry.package = pkgs.pinentry-gnome3;
      # Cache passphrase for 2 hours to reduce prompts
      defaultCacheTtl = 7200;
      maxCacheTtl = 7200;
    };

    # Make pass the default password store (used by bridge CLI)
    home.sessionVariables = {
      PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
    };

    # GPG_TTY must be evaluated per-shell — as a session variable the
    # literal "$(tty)" was exported unevaluated (sessionVariables are
    # sourced once, not interpreted by every tty).
    programs.zsh.initContent = ''
      export GPG_TTY=$(tty)
    '';

    # Ensure pass + gnupg tools exist
    home.packages = [ pkgs.pass pkgs.gnupg ];

    # Optional: bridge the pass store to the SecretService D-Bus API. When on,
    # apps that use libsecret/Electron safeStorage store their secrets in pass
    # (GPG-encrypted) rather than the hardcoded-key `basic` store. gpg-agent
    # (above) supplies the pinentry/unlock path.
    services.pass-secret-service.enable = cfg.secretService.enable;

    # Start with the graphical session, not default.target. Under lingering,
    # default.target starts the daemon before Hyprland imports WAYLAND_DISPLAY
    # and DISPLAY into the user manager. The daemon then has no display, gpg
    # cannot show the GNOME3 pinentry, every locked-key decrypt returns None,
    # and Electron safeStorage reads fail (T3 Code opened empty after a reboot).
    # graphical-session.target is reached only after that environment import.
    systemd.user.services.pass-secret-service = lib.mkIf cfg.secretService.enable {
      Unit = {
        PartOf = lib.mkForce [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Add dependency assertions here if needed
    ];
  };
}