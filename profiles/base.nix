{ lib, pkgs, ... }:
{
  imports = [
    ../modules/system/paths.nix
  ];
  
  time.timeZone = "America/Denver";
  
  networking.firewall.enable = lib.mkDefault true;
  
  services.openssh = {
    enable = lib.mkDefault true;
    settings.PermitRootLogin = "no";
  };
  
  virtualisation.docker.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = "docker";
  
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];
}
