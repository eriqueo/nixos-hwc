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

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Add dependency assertions here if needed
    ];
  };
}