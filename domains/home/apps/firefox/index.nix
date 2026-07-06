# domains/home/apps/firefox/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.firefox;
  theme = import ./parts/theme.nix { inherit lib config; };
  launcher = import ./parts/launcher.nix { inherit lib pkgs; };

  paletteName = lib.attrByPath [ "hwc" "home" "theme" "palette" ] null config;
  palettePath = if paletteName != null then ../../theme/palettes/${paletteName}.nix else null;
  paletteExists = palettePath == null || builtins.pathExists palettePath;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.firefox = {
    enable = lib.mkEnableOption "Firefox browser";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = pkgs.firefox;

      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/behavior.nix { inherit lib pkgs config; })
          (import ./parts/appearance.nix { inherit lib pkgs config; })
        ];

        userChrome  = theme.userChrome;
        userContent = theme.userContent;
      };
    };

    home.packages = launcher.packages;

    home.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
    };

    # Override the upstream firefox.desktop so wofi/rofi/any XDG launcher
    # routes through firefox-hwc (Intel-pinned, VA-API-iHD wrapper) instead
    # of bare firefox. User dir (~/.local/share/applications/firefox.desktop)
    # wins over the package-installed entry under /etc/profiles/.../applications/
    # because XDG_DATA_HOME has higher priority in XDG_DATA_DIRS.
    xdg.desktopEntries.firefox = {
      name = "Firefox";
      genericName = "Web Browser";
      exec = "firefox-hwc %U";
      icon = "firefox";
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
        StartupWMClass = "firefox";
      };
      actions = {
        new-window = {
          name = "New Window";
          exec = "firefox-hwc --new-window %U";
        };
        new-private-window = {
          name = "New Private Window";
          exec = "firefox-hwc --private-window %U";
        };
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.programs.firefox.enable or false;
        message = "programs.firefox must remain enabled when hwc.home.apps.firefox is set";
      }
    ];

    warnings = lib.optionals (paletteName != null && !paletteExists) [
      "Palette \"${paletteName}\" not found under domains/home/theme/palettes; falling back to deep-nord."
    ];
  };
}
