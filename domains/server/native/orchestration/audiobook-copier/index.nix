# domains/server/native/orchestration/audiobook-copier/index.nix
#
# Audiobook Copier Service
# Copies audiobooks from qBittorrent downloads to Audiobookshelf library,
# preserving source files for continued seeding.

{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.server.native.orchestration.audiobookCopier;
  enabled = cfg.enable;

  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);

  # Get username from system configuration
  userName = config.hwc.system.users.user.name;
  userHome = config.users.users.${userName}.home;
  workspaceDir = "${userHome}/.nixos/workspace";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Install audiobook copier script
    systemd.services.audiobook-copier-install = {
      description = "Install audiobook copier assets";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -e
        mkdir -p ${cfg.stateDir}
        mkdir -p ${config.hwc.paths.hot.downloads}/scripts

        # Deploy audiobook copier script from workspace
        cp ${workspaceDir}/hooks/audiobook-copier.py ${config.hwc.paths.hot.downloads}/scripts/
        chmod +x ${config.hwc.paths.hot.downloads}/scripts/audiobook-copier.py

        chown -R 1000:1000 ${cfg.stateDir}
        chmod 755 ${cfg.stateDir}
      '';
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.paths.hot.root != null;
        message = "audiobook-copier requires hwc.paths.hot.root to be defined";
      }
      {
        assertion = config.hwc.paths.media.root != null;
        message = "audiobook-copier requires hwc.paths.media.root to be defined";
      }
      {
        assertion = !cfg.triggerLibraryScan || config.hwc.server.containers.audiobookshelf.enable;
        message = "audiobook-copier triggerLibraryScan requires audiobookshelf container to be enabled";
      }
    ];
  };
}
