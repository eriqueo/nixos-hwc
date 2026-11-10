# domains/home/apps/proton-pass/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.proton-pass;

  # Remove when the packaged bundle registers a Linux tray click handler itself.
  # The exact match makes upstream changes fail the build instead of silently drifting.
  protonPassWithLinuxTrayClick = pkgs.proton-pass.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      asar extract "$out/share/proton-pass/app.asar" pass-tray
      substituteInPlace pass-tray/.webpack/main/index.js \
        --replace-fail "tray.on('double-click', onOpenPassHandler);" \
                       "tray.on('double-click', onOpenPassHandler);
    if (process.platform === 'linux')
        tray.on('click', onOpenPassHandler);"
      asar pack pass-tray "$out/share/proton-pass/app.asar"
      rm -r pass-tray
    '';
  });
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.proton-pass = {
    enable = lib.mkEnableOption "Proton Pass password manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ protonPassWithLinuxTrayClick ];
  };
}
