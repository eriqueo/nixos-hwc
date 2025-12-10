{ pkgs, config, ... }:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
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
    exec bash "${workspace}/nixos/list-services.sh" "$@"
  '';
}
