{ config, lib, pkgs, ... }:

let
  # Python with Tk support (needed for tkinter dialogs)
  py = pkgs.python3Full.withPackages (ps: with ps; [ requests watchdog ]);

  # Where we’ll place your app files
  appDir = "${config.home.homeDirectory}/.local/share/transcript-formatter";

  # A tiny wrapper so you can run `transcript-formatter` in a terminal too
  runner = pkgs.writeShellScriptBin "transcript-formatter" ''
    set -euo pipefail
    cd ${appDir}
    exec ${py}/bin/python ${appDir}/obsidian_transcript_formatter.py
  '';
in
{
  # Make HM back up and overwrite old user files instead of failing on clobber
  home-manager.backupFileExtension = "hm-bak";

  # Put runner on PATH, plus tools your script expects
  home.packages = [
    runner
    pkgs.curl
    pkgs.libnotify # notify-send
  ];

  # Install your application files as managed content
  home.file = {
    "${appDir}/obsidian_transcript_formatter.py".source =
      ../../scripts/transcript-formatter/obsidian_transcript_formatter.py;

    # Keep your prompt alongside the script so the relative path works
    "${appDir}/formatting_prompt.txt".source =
      ../../scripts/transcript-formatter/formatting_prompt.txt;

    # (Optional) keep your nix-shell runner as a reference, but not used by the unit
    "${appDir}/nixos_formatter_runner.sh".source =
      ../../scripts/transcript-formatter/nixos_formatter_runner.sh;
    "${appDir}/nixos_formatter_runner.sh".permissions = "0755";
  };

  # Start the formatter only in a graphical session (Tk + notify need DISPLAY)
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

      # PATH for the service; include curl/notify-send/python env
      Path = [ pkgs.curl pkgs.libnotify py runner ];

      # Environment for your app (optional; your script hardcodes these already)
      Environment = [
        # If you later update your script to read ENV, these are ready:
        "WATCH_FOLDER=${config.home.homeDirectory}/99-vaults/06-contractor/raw"
        "PROMPT_FILE=${appDir}/formatting_prompt.txt"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Make sure user services restart cleanly on HM activation
  systemd.user.startServices = "sd-switch";
}
