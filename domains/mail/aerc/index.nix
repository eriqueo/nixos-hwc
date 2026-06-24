# domains/mail/aerc/index.nix
{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.hwc.mail.aerc;

  # Forked aerc (github:eriqueo/aerc) consumed as a flake-input package, mirroring
  # domains/mail/calendar/index.nix's khalt consumption. Currently a zero-change
  # canary (overrideAttrs on nixpkgs aerc @ 0.21.0); which-key/header patches land
  # later, config-gated default-off.
  aercPkg = import ./package.nix { inherit pkgs inputs; };

  cfgPart    = import ./parts/config.nix   { inherit lib pkgs config aercPkg; };
  bindsPart  = import ./parts/binds.nix  { inherit lib pkgs config; };
  sievePart  = import ./parts/sieve.nix  { inherit lib pkgs config; };
in
{
  options.hwc.mail.aerc.enable = lib.mkEnableOption "aerc terminal email client";

  config = lib.mkIf cfg.enable {
    home.packages = (cfgPart.packages or []);

    home.file = (cfgPart.files "") // (bindsPart.files "") // (sievePart.files "") // {
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
        assertion = !cfg.enable || (config.hwc.mail.accounts or {}) != {};
        message = "aerc requires hwc.mail.accounts";
      }
    ];
  };
}
