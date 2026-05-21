# domains/home/apps/chromium/sys.nix
# System-lane dependencies for Chromium browser
#
# ARCHITECTURE NOTE:
# This sys.nix file defines system-lane options because system evaluates
# before Home Manager. See CHARTER.md Section 5 for sys.nix pattern.

{ config, lib, osConfig ? {}, ... }:

let
  cfg = config.hwc.system.apps.chromium;
in
{
  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.chromium = {
    enable = lib.mkEnableOption "Chromium system integration (dconf, dbus)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      #========================================================================
      # SYSTEM INTEGRATION
      #========================================================================
      # Basic system integration for Chromium browser
      # Ensure dconf is available for browser settings
      programs.dconf.enable = lib.mkDefault true;

      # D-Bus services needed for portal integration
      services.dbus.enable = lib.mkDefault true;

      # No environment.systemPackages - HM provides the chromium binary
      # GPU acceleration via gpu-launch command (from infrastructure.hardware.gpu)

      #========================================================================
      # MANAGED POLICY — session persistence
      #========================================================================
      # Chromium reads any *.json under /etc/chromium/policies/managed/ at
      # startup. RestoreOnStartup=1 makes Chromium restore the previous
      # session on launch, which also preserves session-only cookies across
      # the restart (Chromium treats it as a session continuation, not a
      # new session). That's the win for JobTread and other self-hosted
      # apps that emit session-only auth cookies — without this, those
      # cookies die on browser close and you have to sign in again.
      #
      # Using environment.etc directly instead of programs.chromium.enable
      # because programs.chromium installs chromium system-wide; we already
      # install it via HM (with the proprietary-codec override).
      environment.etc."chromium/policies/managed/hwc.json".text =
        builtins.toJSON {
          RestoreOnStartup = 1;  # 1 = restore last session
        };
    })
    {}
  ];
}