{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on =
    (config.hwc.mail.enable or true) &&
    (config.hwc.mail.mbsync.enable or true) &&
    ((lib.attrValues (config.hwc.mail.accounts or {})) != []);

  render   = import ./parts/render.nix { inherit lib pkgs config; };
  afewCfg  = config.hwc.mail.afew or {};
  afewPkg  = import ../afew/package.nix { inherit lib pkgs; cfg = afewCfg; };
  brCfg = config.hwc.mail.bridge or {};
  maildirRoot =
    let base = (config.hwc.mail.notmuch or {}).maildirRoot or "";
    in if base != "" then base else "${config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail"}/Maildir";
  svc      = import ./parts/service.nix {
    inherit lib pkgs afewPkg;
    haveProton = render.haveProton;
    inherit maildirRoot;
    inherit (render) coreChannels trashChannels;
    statusFile = config.hwc.paths.user.mailSyncStatus or "${config.home.homeDirectory}/.local/state/mail-sync/status.json";
    configDigest = builtins.hashString "sha256" render.mbsyncrc;
    bridgeVersion = lib.getVersion (brCfg.package or pkgs.protonmail-bridge);
    trashTimerEnable = config.hwc.mail.mbsync.trashTimerEnable;
  };
in
{
  options.hwc.mail.mbsync.trashTimerEnable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable the daily isolated Proton Trash synchronization timer";
  };
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on (lib.mkMerge [
    { home.packages = render.packages; }
    { home.file.".mbsyncrc".text = render.mbsyncrc; }
    {
      assertions = [
        {
          assertion = !render.haveProton || lib.length render.trashChannels == 1;
          message = "Proton Trash must render exactly once as an isolated channel";
        }
        {
          assertion = !render.haveProton || lib.hasInfix "!\"Trash\"" render.mbsyncrc;
          message = "The Proton core wildcard must exclude Trash";
        }
      ];
    }
    svc
  ]);
}
