{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on =
    (config.hwc.mail.enable or true) &&
    (config.hwc.mail.mbsync.enable or true) &&
    ((lib.attrValues (config.hwc.mail.accounts or {})) != []);

  render   = import ./parts/render.nix { inherit lib pkgs config; };
  afewCfg  = config.hwc.mail.afew or {};
  afewPkg  = import ../afew/package.nix { inherit lib pkgs; cfg = afewCfg; };
  maildirRoot =
    let base = (config.hwc.mail.notmuch or {}).maildirRoot or "";
    in if base != "" then base else "${config.hwc.paths.user.mail or "/home/eric/400_mail"}/Maildir";
  svc      = import ./parts/service.nix {
    inherit lib pkgs afewPkg;
    haveProton = render.haveProton;
  };
in
{
  # Options: none (uses parent hwc.mail.accounts)
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on (lib.mkMerge [
    { home.packages = render.packages; }
    { home.file.".mbsyncrc".text = render.mbsyncrc; }
    svc
  ]);
}