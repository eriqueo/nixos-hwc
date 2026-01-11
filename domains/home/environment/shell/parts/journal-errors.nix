{ pkgs, config, osConfig ? {}, ...}:

let
  workspace = config.home.homeDirectory + "/.nixos/workspace";
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
    exec bash "${workspace}/monitoring/journal-errors.sh" "$@"
  '';
}