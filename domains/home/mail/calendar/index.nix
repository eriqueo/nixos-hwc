{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.mail.calendar;

  # Handshake: safe access to agenix secrets
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  hasClientId = (osCfg ? age) && (osCfg.age.secrets ? google-oauth-client-id);
  hasClientSecret = (osCfg ? age) && (osCfg.age.secrets ? google-oauth-client-secret);

  clientIdPath = if hasClientId
    then osCfg.age.secrets.google-oauth-client-id.path
    else "/dev/null";
  clientSecretPath = if hasClientSecret
    then osCfg.age.secrets.google-oauth-client-secret.path
    else "/dev/null";

  vdirsyncer = import ./parts/vdirsyncer.nix {
    inherit lib pkgs cfg clientIdPath clientSecretPath;
  };
  khal = import ./parts/khal.nix { inherit lib pkgs cfg; };
  service = import ./parts/service.nix { inherit lib pkgs; };
in
{
  # OPTIONS
  options.hwc.home.mail.calendar = {
    enable = lib.mkEnableOption "calendar sync via khal + vdirsyncer";

    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          email = lib.mkOption {
            type = lib.types.str;
            description = "Google account email address";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "light magenta";
            description = "khal display color for this calendar";
          };
        };
      });
      default = {};
      description = "Google Calendar accounts to sync";
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ pkgs.vdirsyncer pkgs.khal ];

      xdg.configFile."vdirsyncer/config".text = vdirsyncer.config;
      xdg.configFile."khal/config".text = khal.config;

      # Ensure storage directories exist
      home.activation.calendarDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ~/.local/share/vdirsyncer/{status,tokens,calendars}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _:
          "mkdir -p ~/.local/share/vdirsyncer/calendars/${name}"
        ) cfg.accounts)}
      '';
    }

    # systemd timer for periodic sync
    service

    # VALIDATION
    {
      assertions = [
        {
          assertion = cfg.accounts != {};
          message = "hwc.home.mail.calendar requires at least one account";
        }
      ];
    }
  ]);
}
