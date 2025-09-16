{ config, lib, pkgs, ... }:
let
  cfg = {
    name = "eric";
    groups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.zsh;
  };
in {
  users.users.${cfg.name} = {
    isNormalUser = true;
    home = "/home/${cfg.name}";
    shell = cfg.shell;
    extraGroups = cfg.groups;
  };
}