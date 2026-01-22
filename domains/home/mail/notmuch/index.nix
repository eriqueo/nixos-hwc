{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on = (config.hwc.home.mail.enable or true);
  cfg = config.hwc.home.mail.notmuch or {};
  paths = import ./parts/paths.nix { inherit lib config cfg; };
  ident = import ./parts/identity.nix { inherit lib cfg; };
  afewCfg = config.hwc.home.mail.afew or {};
  afewPkg = import ../afew/package.nix { inherit lib pkgs; cfg = afewCfg; };

  cfgPart = import ./parts/config.nix {
    inherit lib pkgs;
    maildirRoot = paths.maildirRoot;
    inherit (ident) userName primaryEmail otherEmails newTags;
    excludeFolders = cfg.excludeFolders or [];

  };

  special = import ./parts/folders.nix { inherit lib config; };
  rules   = import ./parts/rules.nix { inherit lib cfg; };

  hookTxt = import ./parts/hooks.nix {
    inherit lib pkgs special afewPkg;
    afewEnabled = afewCfg.enable or false;
    rulesText = rules.text;
    extraHook = cfg.postNewHook or "";
  };

  searches = import ./parts/searches.nix { inherit lib cfg; };
  dashboardText = builtins.readFile ./parts/dashboard.sh;
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on (lib.mkMerge [
    { home.packages = cfgPart.packages; }
    { programs.notmuch = cfgPart.programs.notmuch; }

    { home.file."${paths.maildirRoot}/.notmuch/hooks/post-new" = {
        text = hookTxt.text;
        executable = true;
      };
    }

    { xdg.configFile."notmuch/searches".text = searches.text; }

    (lib.mkIf (cfg.installDashboard or false) {
      home.file.".local/bin/mail-dashboard" = {
        text = dashboardText;
        executable = true;
      };
    })

    # Auto-sync service and timer
    {
      systemd.user.services.mail-sync = {
        Unit = {
          Description = "Sync mail and update notmuch index";
          After = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          # Wrap sync-mail to check certificate validity first
          ExecStart = pkgs.writeShellScript "mail-sync-wrapper" ''
            set -euo pipefail

            cert_file="/etc/ssl/local/proton-bridge.pem"

            # Check if certificate exists and is not empty
            if [ ! -s "$cert_file" ]; then
              echo "ProtonMail Bridge certificate not available or empty, skipping sync"
              exit 0
            fi

            # Certificate exists, run sync
            exec ${config.home.homeDirectory}/.local/bin/sync-mail
          '';
        };
      };

      systemd.user.timers.mail-sync = {
        Unit = {
          Description = "Timer for mail sync";
          Requires = [ "mail-sync.service" ];
        };
        Timer = {
          OnCalendar = "*:0/5";  # Every 5 minutes
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    }
  ]);
}

  #==========================================================================
  # VALIDATION
  #==========================================================================
