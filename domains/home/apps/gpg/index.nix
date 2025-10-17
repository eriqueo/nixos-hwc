{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.gpg;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # Enable GPG and the user gpg-agent service (pinentry in TTY)
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      pinentry.package = pkgs.pinentry-curses;
    };

    # Make pass the default password store (used by bridge CLI)
    home.sessionVariables = {
      PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
      GPG_TTY = "$(tty)";
    };

    # Ensure pass + gnupg tools exist
    home.packages = [ pkgs.pass pkgs.gnupg ];
  };
}
