# ProtonPass • Session part
# Session-scoped package only. Proton Pass owns its writable app settings.
{ pkgs, ... }:

let
  # Remove when the packaged bundle registers a Linux tray click handler itself.
  # The exact match makes upstream changes fail the build instead of silently drifting.
  protonPassWithLinuxTrayClick = pkgs.proton-pass.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      asar extract "$out/share/proton-pass/app.asar" pass-tray
      substituteInPlace pass-tray/.webpack/main/index.js \
        --replace-fail "if (process.platform === 'win32')
        tray.on('double-click', onOpenPassHandler);" \
                       "if (process.platform === 'linux')
        tray.on('click', onOpenPassHandler);
    if (process.platform === 'win32')
        tray.on('double-click', onOpenPassHandler);"
      asar pack pass-tray "$out/share/proton-pass/app.asar"
      rm -r pass-tray
    '';
  });
in {
  packages = [ protonPassWithLinuxTrayClick ];
}
