# domains/home/apps/transcript-formatter/index.nix
#
# Transcript Formatter — Ollama/Qwen to Obsidian pipeline
#
# NAMESPACE: hwc.home.apps.transcript-formatter.*
# USAGE: hwc.home.apps.transcript-formatter.enable = true;

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.transcript-formatter;

  assetDir = ../../../../workspace/media/youtube-services/transcript-formatter;

  py = pkgs.python3.withPackages (ps: with ps; [ requests watchdog tkinter ]);

  appDir   = "${config.home.homeDirectory}/.local/share/transcript-formatter";
  extraPath = lib.makeBinPath [ pkgs.curl pkgs.libnotify ];

  runner = pkgs.writeShellScriptBin "transcript-formatter" ''
    set -euo pipefail
    cd ${appDir}
    exec ${py}/bin/python ${appDir}/obsidian_transcript_formatter.py
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.transcript-formatter = {
    enable = lib.mkEnableOption "Transcript Formatter (Ollama/Qwen to Obsidian)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = builtins.pathExists (assetDir + "/obsidian_transcript_formatter.py");
        message   = "Missing file: ${toString assetDir}/obsidian_transcript_formatter.py"; }
      { assertion = builtins.pathExists (assetDir + "/formatting_prompt.txt");
        message   = "Missing file: ${toString assetDir}/formatting_prompt.txt"; }
      { assertion = builtins.pathExists (assetDir + "/nixos_formatter_runner.sh");
        message   = "Missing file: ${toString assetDir}/nixos_formatter_runner.sh"; }
    ];

    home.packages = [ runner pkgs.curl pkgs.libnotify ];

    home.file = {
      "${appDir}/obsidian_transcript_formatter.py".source = assetDir + "/obsidian_transcript_formatter.py";
      "${appDir}/formatting_prompt.txt".source            = assetDir + "/formatting_prompt.txt";
      "${appDir}/nixos_formatter_runner.sh" = {
        source = assetDir + "/nixos_formatter_runner.sh";
        executable = true;
      };
    };

    systemd.user.services.transcript-formatter = {
      Unit = {
        Description = "Transcript Formatter (Ollama/Qwen → Obsidian)";
        After  = [ "graphical-session.target" "network-online.target" ];
        Wants  = [ "graphical-session.target" "network-online.target" ];
      };
      Service = {
        Type             = "simple";
        WorkingDirectory = appDir;
        ExecStart        = pkgs.writeShellScript "transcript-formatter-with-check" ''
          if ! ${pkgs.curl}/bin/curl -sf --connect-timeout 2 http://localhost:11434/api/tags > /dev/null 2>&1; then
            echo "Ollama not available, exiting gracefully"
            exit 0
          fi
          exec ${runner}/bin/transcript-formatter
        '';
        Restart          = "no";
        Environment = [
          "WATCH_FOLDER=/mnt/media/transcripts"
          "PROMPT_FILE=${appDir}/formatting_prompt.txt"
          "PATH=${extraPath}:/run/current-system/sw/bin"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.startServices = "sd-switch";
  };
}
