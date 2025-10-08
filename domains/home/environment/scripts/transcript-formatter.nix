# modules/home/environment/scripts/transcript-formatter.nix
{ config, lib, pkgs, ... }:

let
  # Assets dir: from modules/home/environment/scripts -> up 4 -> scripts/transcript-formatter
  assetDir = ../../../../scripts/transcript-formatter;

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
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type             = "simple";
      WorkingDirectory = appDir;
      ExecStart        = "${runner}/bin/transcript-formatter";
      Restart          = "on-failure";
      RestartSec       = "5s";
      Environment = [
        "WATCH_FOLDER=${config.home.homeDirectory}/900_vaults/06-contractor/raw"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
        "PATH=${extraPath}:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.startServices = "sd-switch";
}
