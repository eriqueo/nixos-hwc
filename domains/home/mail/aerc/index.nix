# domains/home/mail/aerc/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.mail.aerc;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config; };
  bindsPart = import ./parts/binds.nix { inherit lib pkgs config; };
in
{
  options.hwc.home.mail.aerc.enable = lib.mkEnableOption "aerc terminal email client";

  config = lib.mkIf cfg.enable {
    home.packages = (cfgPart.packages or []);

    home.file = (cfgPart.files "") // (bindsPart.files "") // {
      ".notmuch-config".source = config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/.config/notmuch/default/config";
    };

    # ← aliases moved here (no more session.nix)
    home.shellAliases = {
      mail      = "aerc";
      mailsync  = "mbsync -a";
      mailindex = "notmuch new";
      urls      = "urlscan";
    };

    home.activation.aercAccounts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m600 -D ${cfgPart.accountsFile} "$HOME/.config/aerc/accounts.conf"
    '';

    assertions = [
      {
        assertion = !cfg.enable || (config.hwc.home.mail.accounts or {}) != {};
        message = "aerc requires hwc.home.mail.accounts";
      }
    ];
  };
}
