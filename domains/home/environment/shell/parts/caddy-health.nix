{ pkgs, config, ... }:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
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
    exec bash "${workspace}/monitoring/caddy-health-check.sh" "$@"
  '';
}
