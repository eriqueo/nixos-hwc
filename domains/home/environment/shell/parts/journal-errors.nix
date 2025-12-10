{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "journal-errors";
  runtimeInputs = with pkgs; [
    bash
    gawk  # awk
    gnused  # sed
    gnugrep  # grep
    coreutils  # wc, sort, uniq, tail
    # journalctl is in system PATH (systemd)
  ];
  text = ''
    exec bash "${workspaceScripts}/monitoring/journal-errors.sh" "$@"
  '';
}
