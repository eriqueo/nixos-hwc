{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.mail.calendar;

  # Handshake: safe access to agenix secrets
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  hasApplePw = (osCfg ? age) && (osCfg.age.secrets ? apple-app-pw);
  applePwPath = if hasApplePw
    then osCfg.age.secrets.apple-app-pw.path
    else "/dev/null";

  vdirsyncer = import ./parts/vdirsyncer.nix {
    inherit lib pkgs cfg applePwPath;
  };
  khal = import ./parts/khal.nix { inherit lib pkgs cfg; };
  service = import ./parts/service.nix { inherit lib pkgs; };
  parser = import ./parts/parser.nix { inherit lib pkgs cfg; };

in
{
  # OPTIONS
  options.hwc.mail.calendar = {
    enable = lib.mkEnableOption "calendar sync via khal + vdirsyncer";

    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          email = lib.mkOption {
            type = lib.types.str;
            description = "Apple ID email address";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "light magenta";
            description = "khal display color for this calendar";
          };
        };
      });
      default = {};
      description = "Apple Calendar accounts to sync via CalDAV";
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ pkgs.vdirsyncer pkgs.khal parser.emailToKhalScript ];

      xdg.configFile = {
          "vdirsyncer/config".text = vdirsyncer.config;
          "khal/config".text = khal.config;
      } // parser.aercConfig;

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
    parser.homeFiles

    # VALIDATION
    {
      assertions = [
        {
          assertion = cfg.accounts != {};
          message = "hwc.mail.calendar requires at least one account";
        }
      ];
    }
  ]);
}
