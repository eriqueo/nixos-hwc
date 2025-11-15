# domains/home/core/xdg-dirs.nix
#
# XDG User Directories Configuration
# Home Manager's built-in XDG support handles user-dirs.dirs creation
# System-level defaults are configured in domains/system/core/paths.nix
{ config, lib, pkgs, ... }:

{
  # XDG user directories are managed by Home Manager's built-in xdg.userDirs option
  # and the system-level /etc/xdg/user-dirs.defaults file
  config = {};
}
