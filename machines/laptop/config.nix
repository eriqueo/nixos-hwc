# nixos-hwc/machines/laptop/config.nix
#
# MACHINE: HWC-LAPTOP
# Declares machine identity and composes profiles; states hardware reality.
# No service implementation or driver minutiae here (Charter v3).
#
# DEPENDENCIES (Upstream):
#   - ./hardware.nix        (host-specific hardware facts)
#   - ../../profiles/base.nix
#   - ../../profiles/workstation.nix
#   - ../../profiles/security.nix
#   - ../../profiles/ai.nix
#
# USED BY (Downstream):
#   - flake.nix (nixosConfigurations.hwc-laptop imports this file)
#
# IMPORTS REQUIRED IN:
#   - flake.nix: modules = [ ./machines/laptop/config.nix ... ]
#
# USAGE:
#   - This file declares facts:
#       * GPU type:        hwc.infrastructure.hardware.gpu.type = "...";
#       * AI services:     hwc.services.ollama.enable = true; models = [ ... ];
#       * Per-machine toggles (e.g., disable Tailscale on laptop).
#   - Secrets go through Agenix (modules/security/secrets), not inline here.

{ config, lib, pkgs, ... }:

{
  ##############################################################################
  ##  MACHINE: HWC-LAPTOP
  ##  This file defines the unique properties and profile composition for the
  ##  hwc-laptop machine, following Charter v3 principles.
  ##############################################################################

  #============================================================================
  # IMPORTS - Compose the machine from profiles and hardware definitions
  #============================================================================
  imports = [
    # Hardware-specific definitions for this machine
    ./hardware.nix


    # Profiles that define the machine's capabilities (orchestration only)
    ../../profiles/base.nix
    ../../profiles/workstation.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
    ../../profiles/hm.nix
    ../../profiles/sys.nix

     
  ];

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

  #============================================================================
  # HWC PROFILE ORCHESTRATION (Facts/Toggles Only)
  #============================================================================

  ## GPU capability (Infrastructure domain implemented in modules/infrastructure/hardware/gpu.nix)
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      containerRuntime = true; # expose GPU to containers (module implements details)
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId  = "PCI:0:2:0";
    };
    powerManagement = {
      smartToggle = true; # Enable gpu-launch, gpu-toggle, gpu-next tools
    };
  };

  ## AI services (Service domain implemented in modules/services/ai/ollama.nix)
  hwc.services.ollama = {
    enable = true;
    # Do NOT set 'enableGpu' here; the service should infer from hwc.infrastructure.hardware.gpu.accel.
    models = [ "llama3:8b" "codellama:13b" "phi3:medium" ];
  };



  ## Security profile toggles (secrets via Agenix; no plaintext in machines)
  # Legacy security configuration removed - now handled by system domain modules

  ## Migration safety: Enable emergency access for new system domain user management
  hwc.system.users.emergencyEnable = true; # DISABLE after confirming login/sudo works

  ## Storage configuration
  hwc.paths = {
    hot = "/home/eric/storage/hot";  # SSD storage for active data
    media = "/home/eric/storage/media";  # Media storage
  };

  ## User/home orchestration (implementation lives in modules/home/*)
  # Legacy hwc.home.ssh removed - SSH now configured via other modules
  # hwc.home.user.fallbackPassword  <-- removed; must be provided via secrets, not inline

  ## Machine-specific service toggles
  hwc.services.vpn.tailscale.enable = false; # Disable tailscale on this machine

  #============================================================================
  # LOW-LEVEL SYSTEM OVERRIDES (Use Sparingly; host-specific)
  #============================================================================
  services.thermald.enable = true;
  services.tlp.enable = true;
  programs.dconf.enable = true;
  services.dunst.enable = true;
  # Note: user account/group wiring should be handled by home/user modules.
  # Removing inline users.users.eric avoids duplication and keeps domains clean.
}
