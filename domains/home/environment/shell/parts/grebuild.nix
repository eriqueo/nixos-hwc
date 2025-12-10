{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "grebuild";
  runtimeInputs = with pkgs; [
    bash
    git
    curl
    # nixos-rebuild is in system PATH
    # sudo is in system PATH
    # systemctl is in system PATH
  ];
  text = ''
    exec bash "${workspaceScripts}/development/grebuild.sh" "$@"
  '';
}
