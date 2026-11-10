# domains/media/orchestration/audiobook-copier/index.nix
#
# Audiobook Copier Service
# Copies audiobooks from qBittorrent downloads to Audiobookshelf library,
# preserving source files for continued seeding.

{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.media.orchestration.audiobookCopier;
  enabled = cfg.enable;

  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);

  paths = config.hwc.paths;
  defaults = {
    SOURCE_DIR = toString cfg.sourceDir;
    DEST_DIR = toString cfg.destDir;
    STATE_DIR = toString cfg.stateDir;
    AUDIOBOOKSHELF_URL = cfg.audiobookshelfUrl;
    TRIGGER_LIBRARY_SCAN = if cfg.triggerLibraryScan then "1" else "0";
    AUDIO_EXTENSIONS = lib.concatStringsSep "," cfg.audioExtensions;
  };
  copierWrapper = pkgs.writeText "audiobook-copier.py" ''
    #!${pythonWithRequests}/bin/python3
    import os, runpy, sys
    sys.path[:0] = "${pkgs.python3Packages.makePythonPath [ pkgs.python3Packages.requests ]}".split(":")
    for name, value in ${builtins.toJSON defaults}.items():
        os.environ.setdefault(name, value)
    runpy.run_path("${../../../../workspace/automation/hooks/audiobook-copier.py}", run_name="__main__")
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.orchestration.audiobookCopier = {
    enable = lib.mkEnableOption "Audiobook copier service";
    sourceDir = lib.mkOption { type = lib.types.path; default = "${config.hwc.paths.hot.downloads}/books"; description = "Source directory for downloaded audiobooks"; };
    destDir = lib.mkOption { type = lib.types.path; default = toString config.hwc.paths.media.audiobooks; description = "Destination directory for Audiobookshelf library"; };
    stateDir = lib.mkOption { type = lib.types.path; default = "${paths.state}/audiobook-copier"; description = "State directory for tracking processed audiobooks"; };
    triggerLibraryScan = lib.mkOption { type = lib.types.bool; default = true; description = "Trigger Audiobookshelf library scan after copying"; };
    audiobookshelfUrl = lib.mkOption { type = lib.types.str; default = "http://localhost:${toString config.hwc.media.audiobookshelf.port}"; description = "Audiobookshelf API URL"; };
    audioExtensions = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "mp3" "m4a" "m4b" "flac" "opus" "ogg" "wav" "aac" ]; description = "Audio file extensions to detect audiobooks"; };
  };


  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    { system.build.audiobookCopierWrapper = copierWrapper; }
    (lib.mkIf enabled {
    # CRITICAL state and legacy .abs-copied markers retain their existing format.
    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0755 eric users -" ];
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

        install -m 0755 ${copierWrapper} ${paths.hot.downloads}/scripts/audiobook-copier.py
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
        assertion = !cfg.triggerLibraryScan || config.hwc.media.audiobookshelf.enable;
        message = "audiobook-copier triggerLibraryScan requires audiobookshelf container to be enabled";
      }
    ];
  }) ];
}
