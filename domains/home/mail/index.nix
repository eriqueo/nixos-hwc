{ lib, ... }:
let
  dir = builtins.readDir ./.;

  # child program dirs that have an index.nix (mbsync, msmtp, notmuch, abook, bridge,…)
  kids = lib.filter (n:
    dir.${n} == "directory"
    && n != "accounts"
    && builtins.pathExists (./. + "/${n}/index.nix")
  ) (lib.attrNames dir);

  children = map (n: ./. + "/${n}/index.nix")
              (lib.sort (a: b: a < b) kids);

  haveAccounts = builtins.pathExists (./accounts/index.nix);
in
{
  imports =
    [ ./options.nix ]
    ++ lib.optional haveAccounts (./accounts/index.nix)
    ++ children;
}
