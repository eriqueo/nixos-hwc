{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "charter-lint";
  runtimeInputs = with pkgs; [
    bash
    gnugrep  # grep
    gnused  # sed
    gawk  # awk
    findutils  # find
    coreutils  # wc, sort, uniq, cut, etc
  ];
  text = ''
    exec bash "${workspaceScripts}/development/charter-lint.sh" "$@"
  '';
}
