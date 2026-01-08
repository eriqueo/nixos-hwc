# modules/home/environment/scripts/transcript-formatter.nix
{ config, lib, pkgs, ... }:

let
  # Assets dir: from modules/home/environment/scripts -> up 4 -> workspace/projects/productivity/transcript-formatter
  assetDir = ../../../../workspace/projects/productivity/transcript-formatter;

  # Python w/ tkinter + deps (python3Full is gone)
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
  assertions = [
    { assertion = builtins.pathExists (assetDir + "/obsidian_transcript_formatter.py");
      message   = "Missing file: ${assetDir}/obsidian_transcript_formatter.py"; }
    { assertion = builtins.pathExists (assetDir + "/formatting_prompt.txt");
      message   = "Missing file: ${assetDir}/formatting_prompt.txt"; }
    { assertion = builtins.pathExists (assetDir + "/nixos_formatter_runner.sh");
      message   = "Missing file: ${assetDir}/nixos_formatter_runner.sh"; }
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
      # Removed PartOf to prevent session restarts during service updates
    };
    Service = {
      Type             = "simple";
      WorkingDirectory = appDir;
      # Wrapper script that checks Ollama availability before running
      ExecStart        = pkgs.writeShellScript "transcript-formatter-with-check" ''
        # Check if Ollama is available
        if ! ${pkgs.curl}/bin/curl -sf --connect-timeout 2 http://localhost:11434/api/tags > /dev/null 2>&1; then
          echo "Ollama not available, service will retry in 30 seconds"
          sleep infinity  # Keep service "running" but idle
        fi
        # Ollama is available, run the formatter
        exec ${runner}/bin/transcript-formatter
      '';
      Restart          = "on-failure";
      RestartSec       = "30s";  # Increased from 5s to reduce crash loop frequency
      Environment = [
        "WATCH_FOLDER=/mnt/media/transcripts"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
        "PATH=${extraPath}:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.startServices = "sd-switch";
}
