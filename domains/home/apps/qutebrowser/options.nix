{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.qutebrowser = {
    enable = lib.mkEnableOption "Keyboard-focused browser with a minimal GUI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package to use for qutebrowser.
        If null, uses the default from nixpkgs.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional packages to install alongside qutebrowser.
        Useful for plugins, extensions, or dependencies.
      '';
    };
  };
}