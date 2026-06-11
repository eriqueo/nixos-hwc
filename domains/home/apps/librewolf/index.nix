# domains/home/apps/librewolf/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.librewolf;
  theme = import ./parts/theme.nix { inherit lib config; };
  launcher = import ./parts/launcher.nix { inherit lib pkgs; };

  hasProfiles = builtins.hasAttr "profiles" (config.programs.librewolf or {});

  paletteName = lib.attrByPath [ "hwc" "home" "theme" "palette" ] null config;
  palettePath = if paletteName != null then ../../theme/palettes/${paletteName}.nix else null;
  paletteExists = palettePath == null || builtins.pathExists palettePath;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.librewolf = {
    enable = lib.mkEnableOption "Librewolf browser";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    programs.librewolf = {
      enable = true;
      package = pkgs.librewolf;

      # Use profiles API if available (HM unstable), otherwise use old settings API (HM 24.05)
    } // lib.optionalAttrs hasProfiles {
      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/behavior.nix { inherit lib pkgs config; })
          (import ./parts/appearance.nix { inherit lib pkgs config; })
        ];

        userChrome  = theme.userChrome;
        userContent = theme.userContent;
      };
    } // lib.optionalAttrs (!hasProfiles) {
      # Fallback for HM 24.05: use old settings format
      settings = lib.mkMerge [
        (import ./parts/behavior.nix { inherit lib pkgs config; })
        (import ./parts/appearance.nix { inherit lib pkgs config; })
      ];
    };

    home.packages = launcher.packages;

    home.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
    };

    # Default browser registration — wofi/portals/xdg-open resolve http(s)
    # and html to LibreWolf.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = [ "librewolf.desktop" ];
        "x-scheme-handler/https" = [ "librewolf.desktop" ];
        "text/html" = [ "librewolf.desktop" ];
      };
    };

    # Override the upstream librewolf.desktop so wofi/rofi/any XDG launcher
    # routes through librewolf-hwc (Intel-pinned, VA-API-iHD wrapper) instead
    # of bare librewolf. User dir (~/.local/share/applications/librewolf.desktop)
    # wins over the package-installed entry under /etc/profiles/.../applications/
    # because XDG_DATA_HOME has higher priority in XDG_DATA_DIRS.
    xdg.desktopEntries.librewolf = {
      name = "LibreWolf";
      genericName = "Web Browser";
      exec = "librewolf-hwc %U";
      icon = "librewolf";
      type = "Application";
      terminal = false;
      startupNotify = true;
      categories = [ "Network" "WebBrowser" ];
      mimeType = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "application/vnd.mozilla.xul+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      settings = {
        StartupWMClass = "librewolf";
      };
      actions = {
        new-window = {
          name = "New Window";
          exec = "librewolf-hwc --new-window %U";
        };
        new-private-window = {
          name = "New Private Window";
          exec = "librewolf-hwc --private-window %U";
        };
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.programs.librewolf.enable or false;
        message = "programs.librewolf must remain enabled when hwc.home.apps.librewolf is set";
      }
    ];

    warnings = lib.optionals (paletteName != null && !paletteExists) [
      "Palette \"${paletteName}\" not found under domains/home/theme/palettes; falling back to deep-nord."
    ];
  };
}