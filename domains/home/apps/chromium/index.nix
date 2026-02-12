# HWC Charter Module/domains/home/apps/chromium/index.nix
#
# Home UI: Chromium Browser Configuration
# Charter v7 compliant - Web browser configuration with universal domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#   Universal domains: behavior.nix (keybindings/shortcuts), session.nix (services), appearance.nix (styling)

{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.chromium;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;
in {
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Use regular chromium with proprietary codecs enabled for video playback
    home.packages = [
      (pkgs.chromium.override {
        enableWideVine = true;  # Includes H.264/AAC codecs + WideVine DRM
      })
    ];

    # Custom desktop entry with GPU acceleration and hardware video decode
    xdg.desktopEntries.chromium-browser = {
      name = "Chromium";
      genericName = "Web Browser";
      exec = "chromium --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE --use-gl=desktop --disable-features=UseChromeOSDirectVideoDecoder --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist %U";
      icon = "chromium";
      type = "Application";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" ];
      actions = {
        new-window = {
          name = "New Window";
          exec = "chromium --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE --use-gl=desktop --disable-features=UseChromeOSDirectVideoDecoder --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist";
        };
        new-private-window = {
          name = "New Incognito Window";
          exec = "chromium --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE --use-gl=desktop --disable-features=UseChromeOSDirectVideoDecoder --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --incognito";
        };
      };
    };

    # Future: Add universal domain parts
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
    # session = import ./parts/session.nix { inherit lib pkgs config; };
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      {
        assertion = !cfg.enable || !isNixOSHost || lib.attrByPath [ "hwc" "system" "apps" "chromium" "enable" ] false osConfig;
        message = ''
          hwc.home.apps.chromium is enabled but hwc.system.apps.chromium is not.
          System integration (dconf, dbus) is required for chromium.
          Enable hwc.system.apps.chromium in machine config.
        '';
      }
    ];
  };
}
