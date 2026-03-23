# domains/home/mail/calendar/parts/parser.nix
# Pure function — returns { emailToKhalScript, aercConfig, homeFiles }
{ lib, pkgs, cfg }:

let
  py = pkgs.python3.withPackages (ps: with ps; [ dateparser ics ]);

  defaultCal = lib.head (lib.attrNames cfg.accounts);

  emailToKhalScript = pkgs.writeShellScriptBin "email-to-khal" ''
    exec ${py}/bin/python3 ${./email-to-khal.py} "$@"
  '';
in
{
  inherit emailToKhalScript;

  # aerc filter config (xdg.configFile entries)
  aercConfig = {};

  # home.file entries (merged into mkMerge)
  homeFiles = {};
}
