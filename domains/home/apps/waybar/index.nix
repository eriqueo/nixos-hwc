# domains/home/apps/waybar/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.waybar;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;

  scriptPkgs = with pkgs; [
    coreutils gnugrep gawk gnused procps util-linux
    kitty wofi jq curl
    networkmanager iw ethtool
    libnotify mesa-demos nvtopPackages.full lm_sensors acpi powertop
    speedtest-cli hyprland
    baobab btop brightnessctl
    power-profiles-daemon
  ];

  scriptPathBin = lib.makeBinPath scriptPkgs;

  behavior  = import ./parts/behavior.nix  { inherit config lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit pkgs lib; pathBin = scriptPathBin; };
  launchPkg = scripts.launch;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.waybar = {
    enable = lib.mkEnableOption "Waybar status bar";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Include waybar packages, script dependencies, and generated script bins.
    home.packages = packages ++ scriptPkgs ++ (lib.attrValues scripts);

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
      systemd.enable = true;
    };

    xdg.configFile."waybar/style.css".text = appearance;

    # Lid sleep state: no init service — the ignore-file simply doesn't exist
    # after login, so lid close suspends by default. waybar-lid-toggle creates/
    # deletes /run/user/$UID/hwc-lid-ignore to flip it — no D-Bus, no logind.
    # acpid reads the file (machines/laptop/config.nix hwc-lid-close handler).

    # Restart waybar after Home Manager activation (rebuild switch).
    # HM reloads the daemon but doesn't restart changed services by default.
    # Run waybar via systemd so it survives rebuilds and restarts cleanly.
    # (Restart-on-switch comes from systemd.user.startServices = "sd-switch"
    # in profiles/base/home.nix — the old restartWaybar activation hack is gone.)
    # Wait for XDG portals to avoid race condition on startup.
    systemd.user.services.waybar = {
      Unit = {
        Description = lib.mkForce "Waybar status bar";
        After = [ "graphical-session.target" "xdg-desktop-portal.service" "xdg-desktop-portal-hyprland.service" ];
        Wants = [ "xdg-desktop-portal.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.mkForce "${launchPkg}/bin/waybar-launch";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        Restart = lib.mkForce "always";
        RestartSec = 3;
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "waybar"; })

      # Home-lane dependencies
      {
        assertion = !cfg.enable || config.hwc.home.apps.swaync.enable;
        message = "waybar requires swaync for notification center (custom/notification widget)";
      }
    ];

    # Runtime dependencies enforced via scriptPkgs PATH:
    # - kitty, wofi, btop: Runtime availability ensured via scriptPkgs inclusion (line 15, 19)
    # - wlogout: Called by custom/power widget, must be installed system-wide or in home packages
    #
    # GPU scripts dependency: waybar-gpu-status widget calls gpu-toggle (from infrastructure.hardware.gpu)
    # This dependency is enforced at runtime - gpu-toggle must exist in PATH
    # Infrastructure GPU module provides: gpu-toggle, gpu-status, gpu-launch, gpu-next
    # Note: Cross-domain assertions (HM -> System) can't be enforced at build time
    #       Runtime failure will occur if infrastructure.hardware.gpu.powerManagement.smartToggle is not enabled
  };
}
