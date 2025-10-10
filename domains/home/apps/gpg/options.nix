{ config, lib, pkgs, ... }:
{
  options.hwc.home.apps.gpg = {
    enable = lib.mkEnableOption "GnuPG (gpg) tools and user gpg-agent for pass";
  };
}
