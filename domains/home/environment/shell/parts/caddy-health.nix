{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "caddy-health";
  runtimeInputs = with pkgs; [
    bash
    curl
    jq
    gnugrep  # grep
    gawk  # awk
  ];
  text = ''
    exec bash "${workspaceScripts}/monitoring/caddy-health-check.sh" "$@"
  '';
}
