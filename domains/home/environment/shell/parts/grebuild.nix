{ pkgs, config, osConfig ? {}, ...}:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
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
    exec bash "${workspace}/nixos/grebuild.sh" "$@"
  '';
}