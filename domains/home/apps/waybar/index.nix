# modules/home/apps/waybar/index.nix

# This module uses a special feature of NixOS flakes to get the
# pkgs set that corresponds to the final system configuration.
{ config, lib, pkgs, osConfig, ... }:

let
  enabled = config.hwc.home.apps.waybar.enable or false;

  # scriptPkgs: All runtime dependencies needed by waybar custom scripts.
  # NVIDIA tools (nvidia-smi, nvidia-settings) are provided by system configuration
  # in the infrastructure domain and don't need to be included here.
  scriptPkgs = with pkgs; [
    coreutils gnugrep gawk gnused procps util-linux
    kitty wofi jq curl
    networkmanager iw ethtool
    libnotify mesa-demos nvtopPackages.full lm_sensors acpi powertop
    speedtest-cli hyprland
    baobab btop
  ];

  # Create the PATH string from scriptPkgs for runtime script execution.
  scriptPathBin = lib.makeBinPath scriptPkgs;

  # Import parts: pure functions that build waybar configuration components.
  cfg       = config.hwc.home.apps.waybar;
  theme     = import ./parts/theme.nix     { inherit config lib; };
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit pkgs lib; pathBin = scriptPathBin; };

in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Include waybar packages, script dependencies, and generated script bins.
    home.packages = packages ++ scriptPkgs ++ (lib.attrValues scripts);

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
      systemd.enable = false;
    };

    xdg.configFile."waybar/style.css".text = appearance;

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled
      {
        assertion = !enabled || (osConfig.hwc.system.apps.waybar.enable or false);
        message = ''
          hwc.home.apps.waybar is enabled but hwc.system.apps.waybar is not.
          System-lane validation checks are required for waybar dependencies.
          Enable hwc.system.apps.waybar in machine config.
        '';
      }

      # Home-lane dependencies
      {
        assertion = !enabled || config.hwc.home.apps.swaync.enable;
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