# domains/system/core/index.nix — aggregates core system functionality
{ lib, config, pkgs, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================

  #============================================================================
  # PACKAGES OPTIONS
  #============================================================================
  options.hwc.system.core.packages = {
    enable = lib.mkEnableOption "core package bundles" // { default = true; };

    base.enable = lib.mkEnableOption "essential system packages for all machines" // { default = true; };

    server.enable = lib.mkEnableOption "server-focused system packages";

    security = {
      enable = lib.mkEnableOption "backup/security tooling bundle";

      protonDrive.enable = lib.mkEnableOption "Proton Drive integration helpers";

      extraTools = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Additional security/backup packages to install";
      };

      monitoring.enable = lib.mkEnableOption "security/backup monitoring helpers";
    };
  };

  # Backward compat: hwc.system.core.shell.enable maps to packages
  options.hwc.system.core.shell.enable = lib.mkEnableOption "core shell (alias for packages.base)" // { default = true; };

  # nix-ld GUI library set — graphical roles (desktop, gaming) flip this
  # instead of each carrying a verbatim copy of the list. Base role enables
  # nix-ld itself with the core (non-GUI) libs.
  options.hwc.system.core.nixld.guiLibs.enable =
    lib.mkEnableOption "X11/GTK/audio library set for nix-ld on graphical machines";

  imports = [
    ./packages.nix
    ../../paths/paths.nix
    ./login/index.nix
    ./coredump.nix
    ./authentik/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf config.hwc.system.core.nixld.guiLibs.enable {
    programs.nix-ld.libraries = with pkgs; [
      gtk3 pango cairo gdk-pixbuf atk
      libdrm mesa alsa-lib cups libpulseaudio
      libx11 libxcomposite libxcursor libxdamage libxext libxfixes
      libxi libxrandr libxrender libxtst libxcb libxscrnsaver
      at-spi2-atk at-spi2-core
      libgbm libxkbcommon
    ];
  };
}
