{ config, lib, pkgs, ... }:

let
  # Python with Tk support + deps
  py = pkgs.python3Full.withPackages (ps: with ps; [ requests watchdog ]);

  appDir = "${config.home.homeDirectory}/.local/share/transcript-formatter";

  runner = pkgs.writeShellScriptBin "transcript-formatter" ''
    set -euo pipefail
    cd ${appDir}
    exec ${py}/bin/python ${appDir}/obsidian_transcript_formatter.py
  '';
in
{
  # Put runner on PATH, plus tools the script calls
  home.packages = [
    runner
    pkgs.curl
    pkgs.libnotify
  ];

  # Managed app files
  home.file = {
    "${appDir}/obsidian_transcript_formatter.py".source =
      ../../scripts/transcript-formatter/obsidian_transcript_formatter.py;

    "${appDir}/formatting_prompt.txt".source =
      ../../scripts/transcript-formatter/formatting_prompt.txt;

    "${appDir}/nixos_formatter_runner.sh".source =
      ../../scripts/transcript-formatter/nixos_formatter_runner.sh;
    "${appDir}/nixos_formatter_runner.sh".permissions = "0755";
  };

  # User service – start in graphical session
  systemd.user.services.transcript-formatter = {
    Unit = {
      Description = "Transcript Formatter (Ollama/Qwen → Obsidian)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "graphical-session.target" "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = appDir;
      ExecStart = "${runner}/bin/transcript-formatter";
      Restart = "on-failure";
      RestartSec = "5s";

      # Optional environment; your script works without it
      Environment = [
        "WATCH_FOLDER=${config.home.homeDirectory}/99-vaults/06-contractor/raw"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
      ];
    };
    # IMPORTANT: lower-case path (HM/NixOS wrapper to extend $PATH)
    path = [ pkgs.curl pkgs.libnotify py runner ];

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Correct place for this (below) is the NixOS-level HM module, not here:
  # systemd.user.startServices can stay here:
  systemd.user.startServices = "sd-switch";
}
