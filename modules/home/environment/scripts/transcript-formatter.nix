{ config, lib, pkgs, ... }:

let
  # Python env for the script (tkinter included)
  py = pkgs.python3.withPackages (ps: with ps; [ requests watchdog tkinter ]);

  appDir = "${config.home.homeDirectory}/.local/share/transcript-formatter";

  # Small wrapper so ExecStart is an absolute path and python is fixed
  runner = pkgs.writeShellScriptBin "transcript-formatter" ''
    set -euo pipefail
    cd ${appDir}
    exec ${py}/bin/python ${appDir}/obsidian_transcript_formatter.py
  '';

  # Add tools the script calls by name (notify-send, curl)
  extraPath = lib.makeBinPath [ pkgs.libnotify pkgs.curl runner ];
in
{
  # put runner & tools on PATH for interactive shells (nice-to-have)
  home.packages = [ runner pkgs.curl pkgs.libnotify ];

  # managed app files
  home.file = {
    "${appDir}/obsidian_transcript_formatter.py" = {
      source = ../../scripts/transcript-formatter/obsidian_transcript_formatter.py;
      mode   = "0644";
    };

    "${appDir}/formatting_prompt.txt" = {
      source = ../../scripts/transcript-formatter/formatting_prompt.txt;
      mode   = "0644";
    };

    "${appDir}/nixos_formatter_runner.sh" = {
      source = ../../scripts/transcript-formatter/nixos_formatter_runner.sh;
      mode   = "0755";
    };
  };

  # user service
  systemd.user.services.transcript-formatter = {
    Unit = {
      Description = "Transcript Formatter (Ollama/Qwen → Obsidian)";
      After  = [ "graphical-session.target" "network-online.target" ];
      Wants  = [ "graphical-session.target" "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type             = "simple";
      WorkingDirectory = appDir;
      ExecStart        = "${runner}/bin/transcript-formatter";
      Restart          = "on-failure";
      RestartSec       = "5s";
      Environment = [
        "WATCH_FOLDER=${config.home.homeDirectory}/99-vaults/06-contractor/raw"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
        # HM does NOT support a `path = [...]`; inject PATH explicitly:
        "PATH=${extraPath}:/run/current-system/sw/bin"
      ];
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  # start/stop user units on switch
  systemd.user.startServices = "sd-switch";
}
