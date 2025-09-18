{ config, lib, pkgs, ... }:

let
  # Where this module file sits
  here = ./.;

  # Assets directory (three levels up from modules/home/environment/scripts/)
  assetDir = ../../../scripts/transcript-formatter;

  # Python with tkinter + deps (python3Full is gone in recent nixpkgs)
  py = pkgs.python3.withPackages (ps: with ps; [ requests watchdog tkinter ]);

  # Install dir in $HOME (what the script expects)
  appDir = "${config.home.homeDirectory}/.local/share/transcript-formatter";

  # Small wrapper on PATH for systemd service
  extraPath = lib.makeBinPath [ pkgs.curl pkgs.libnotify ];

  # CLI runner on PATH
  runner = pkgs.writeShellScriptBin "transcript-formatter" ''
    set -euo pipefail
    cd ${appDir}
    exec ${py}/bin/python ${appDir}/obsidian_transcript_formatter.py
  '';
in
{
  # Fail early if assets are missing (clear message instead of cryptic path error)
  assertions = [
    {
      assertion = builtins.pathExists (assetDir + "/obsidian_transcript_formatter.py");
      message   = "Missing file: ${assetDir}/obsidian_transcript_formatter.py";
    }
    {
      assertion = builtins.pathExists (assetDir + "/formatting_prompt.txt");
      message   = "Missing file: ${assetDir}/formatting_prompt.txt";
    }
    {
      assertion = builtins.pathExists (assetDir + "/nixos_formatter_runner.sh");
      message   = "Missing file: ${assetDir}/nixos_formatter_runner.sh";
    }
  ];

  # Binaries used by the runner
  home.packages = [ runner pkgs.curl pkgs.libnotify ];

  # Files to drop into $HOME
  home.file = {
    "${appDir}/obsidian_transcript_formatter.py".source =
      assetDir + "/obsidian_transcript_formatter.py";

    "${appDir}/formatting_prompt.txt".source =
      assetDir + "/formatting_prompt.txt";

    "${appDir}/nixos_formatter_runner.sh" = {
      source = assetDir + "/nixos_formatter_runner.sh";
      executable = true;        # HM supports 'executable', not 'mode'/'permissions'
    };
  };

  # User service (starts in graphical session)
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
        # script reads these (your python uses PROMPT_FILE if provided)
        "WATCH_FOLDER=${config.home.homeDirectory}/99-vaults/06-contractor/raw"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
        # Give the service a reliable PATH
        "PATH=${extraPath}:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Start/stop HM user units on switch
  systemd.user.startServices = "sd-switch";
}
