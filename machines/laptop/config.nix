# In: machines/laptop/config.nix
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
    ./home.nix

    # Profiles that define the machine's capabilities
    ../../profiles/base.nix
    ../../profiles/workstation.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
  ];

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

  #============================================================================
  # HWC PROFILE ORCHESTRATION
  # This section sets the high-level options for the imported profiles.
  # It is the single source of truth for this machine's configuration.
  #============================================================================

  # --- GPU Profile Configuration (from profiles/base.nix) ---
  hwc.gpu = {
    type = "nvidia";
    nvidia = {
      containerRuntime = true; # Enable GPU capabilities for containers
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId = "PCI:0:2:0";
    };
  };

  # --- AI Profile Configuration (from profiles/ai.nix) ---
  hwc.services.ollama = {
    enable = true;
    enableGpu = true; # Tell the Ollama service to consume the GPU capability
    models = [ "llama3:8b" "codellama:13b" "phi3:medium" ]; # Machine-specific model list
  };

  # --- Workstation Profile Configuration (from profiles/workstation.nix) ---
  hwc.desktop = {
    waybar.enable = true;
    apps = {
      enable = true;
      browser.firefox = true;
      multimedia.enable = true;
      productivity.enable = true;
    };
  };

  # --- Security Profile Configuration (from profiles/security.nix) ---
  hwc.secrets.enable = true;
  hwc.security = {
    # Set to 'false' after migration is confirmed
    emergencyAccess.enable = true;
    emergencyAccess.password = "il0wwlm?";
    # Path to this machine's specific age key
    ageKeyFile = "/etc/age/keys.txt";
  };

  # --- User Configuration (from profiles/base.nix) ---
  hwc.home.ssh.enable = true;
  hwc.home.user.fallbackPassword = "il0wwlm?";

  # --- Service Overrides ---
  hwc.services.vpn.tailscale.enable = false; # Disable tailscale on this machine

  #============================================================================
  # LOW-LEVEL SYSTEM OVERRIDES (Use Sparingly)
  #============================================================================
  services.thermald.enable = true;
  services.tlp.enable = true;

  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };
}
