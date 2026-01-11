{ pkgs, config, osConfig ? {}, ...}:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
in
pkgs.writeShellApplication {
  name = "secret";
  runtimeInputs = with pkgs; [
    bash
    age
    ripgrep
    findutils
    gawk
    coreutils
    gnused
    nix
    # sudo is in system PATH
  ];
  text = ''
    exec bash "${workspace}/utilities/secret-manager.sh" "$@"
  '';
}