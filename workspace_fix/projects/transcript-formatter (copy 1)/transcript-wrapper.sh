#!/usr/bin/env bash
set -euo pipefail
exec "${HOME}/.local/share/transcript-formatter/venv/bin/python" "${HOME}/.local/share/transcript-formatter/formatter.py" "$@"

Home-Manager integration (drop into hosts/laptop/home.nix, adjusting paths if your vault uses a different root). This creates the venv reproducibly from nixpkgs python, installs requests, puts files in place, and schedules runs every 15 minutes. It also sets TRANSCRIPTS_INPUT to your scraper output and TRANSCRIPTS_OUTPUT to your cleaned destination.

{ config, lib, pkgs, ... }:

let
  py = pkgs.python312;
  pyEnv = py.withPackages (ps: with ps; [ requests ]);
  dataRoot = "${config.xdg.dataHome}";
  appRoot = "${dataRoot}/transcript-formatter";
  inputDir = "${dataRoot}/transcripts/input_transcripts";
  outputDir = "${dataRoot}/transcripts/cleaned_transcripts";
  wrapperBin = "${config.home.homeDirectory}/.local/bin/transcript-formatter";
in {
  home.packages = [ pyEnv pkgs.curl ];

  xdg.enable = true;

  home.file = {
    ".local/share/transcript-formatter/formatter.py".text = builtins.readFile ./formatter.py;
    ".local/share/transcript-formatter/formatter.py".executable = true;

    ".local/bin/transcript-formatter".text = builtins.readFile ./transcript-wrapper.sh;
    ".local/bin/transcript-formatter".executable = true;
  };

  home.activation.transcriptFormatter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${appRoot} ${inputDir} ${outputDir}
    if [ ! -d "${appRoot}/venv" ]; then
      ${pyEnv}/bin/python -m venv "${appRoot}/venv"
      "${appRoot}/venv/bin/pip" install --no-input --upgrade pip
      "${appRoot}/venv/bin/pip" install --no-input requests
    fi
  '';

  systemd.user.services.transcript-formatter = {
    Unit.Description = "Format and structure transcript Markdown using local Ollama";
    Service = {
      Type = "simple";
      Environment = [
        "TRANSCRIPTS_INPUT=${inputDir}"
        "TRANSCRIPTS_OUTPUT=${outputDir}"
        "OLLAMA_HOST=http://127.0.0.1:11434"
        "OLLAMA_MODEL=llama3"
        "OLLAMA_TEMPERATURE=0.2"
        "OLLAMA_TOP_P=0.9"
        "PATH=${config.home.profileDirectory}/bin:${config.home.sessionPath}"
      ];
      ExecStart = "${wrapperBin}";
      WorkingDirectory = "%h";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.timers.transcript-formatter = {
    Unit.Description = "Run transcript formatter periodically";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "15m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  services.ollama.enable = true;
}
