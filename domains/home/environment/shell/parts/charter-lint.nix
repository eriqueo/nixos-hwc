{ pkgs, config, ... }:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
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
    exec bash "${workspace}/nixos/charter-lint.sh" "$@"
  '';
}
