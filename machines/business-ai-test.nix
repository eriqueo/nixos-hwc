{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/business.nix
    ../profiles/ai.nix
    ../profiles/monitoring.nix
  ];
  
  networking.hostName = "business-ai-test";
  
  # GPU for AI workloads
  hwc.gpu.nvidia = {
    enable = true;
    containerRuntime = true;
  };
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
  
  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "24.05";
}
