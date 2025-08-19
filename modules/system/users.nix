{ config, lib, pkgs, ... }:
{
  users.users.eric = {
    isNormalUser = true;
    description = "Eric";
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "media"
      "video"
      "audio"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here from your current config
    ];
  };

  # Media group for shared access
  users.groups.media = {};

  # Enable sudo
  security.sudo.wheelNeedsPassword = false;
}
