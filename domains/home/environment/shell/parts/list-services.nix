{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "list-services";
  runtimeInputs = with pkgs; [
    bash
    podman
    gawk  # awk
    gnugrep  # grep
    # systemctl is in system PATH (systemd)
  ];
  text = ''
    exec bash "${workspaceScripts}/development/list-services.sh" "$@"
  '';
}
