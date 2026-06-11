# domains/home/apps/chromium/index.nix
{ lib, pkgs, config, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.chromium;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;
  launcher = import ./parts/launcher.nix { inherit lib pkgs; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.chromium = {
    enable = lib.mkEnableOption "Chromium browser";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Use regular chromium with proprietary codecs enabled for video playback.
    # chromium-hwc is a wrapper that picks Intel (ANGLE-GL) vs NVIDIA
    # (ANGLE-Vulkan + PRIME) flags based on /tmp/gpu-mode (see gpu-toggle).
    home.packages = [
      (pkgs.chromium.override {
        enableWideVine = true;  # Includes H.264/AAC codecs + WideVine DRM
      })
    ] ++ launcher.packages;

    # Desktop entry calls the wrapper so GPU mode flips automatically pick
    # the right flag set on the next launch.
    xdg.desktopEntries.chromium-browser = {
      name = "Chromium";
      genericName = "Web Browser";
      exec = "chromium-hwc %U";
      icon = "chromium";
      type = "Application";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" ];
      actions = {
        new-window = {
          name = "New Window";
          exec = "chromium-hwc";
        };
        new-private-window = {
          name = "New Incognito Window";
          exec = "chromium-hwc --incognito";
        };
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "chromium"; })
    ];
  };
}
