# nixos-hwc/modules/home/cli.nix
#
# CLI - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.home.cli.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/home/cli.nix
#
# USAGE:
#   hwc.home.cli.enable = true;
#   # TODO: Add specific usage examples

 { config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.cli;
     in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
       options.hwc.home.cli = {
         enable = lib.mkEnableOption "CLI tools and utilities";

         modernUnix = lib.mkOption {
           type = lib.types.bool;
           default = true;
           description = "Enable modern Unix replacements (eza,
     bat, fd, etc.)";
         };

         git = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Git configuration";
           };
           userName = lib.mkOption {
             type = lib.types.str;
             default = "Eric";
             description = "Git user name";
           };
           userEmail = lib.mkOption {
             type = lib.types.str;
             default = "eric@hwc.moe";
             description = "Git user email";
           };
         };
       };


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
       config = lib.mkIf cfg.enable {
         environment.systemPackages = with pkgs; [
           # Core utilities
           curl
           wget
           unzip
           zip
           tree
           htop
           btop
           ncdu

           # Search and text processing
           ripgrep
           fzf
           jq
           yq

         ] ++ lib.optionals cfg.modernUnix [
           # Modern Unix replacements
           eza          # ls replacement
           bat          # cat replacement
           fd           # find replacement
           zoxide       # cd replacement
           procs        # ps replacement
           dust         # du replacement
         ];

         # Git configuration
         programs.git = lib.mkIf cfg.git.enable {
           enable = true;
         };

         # Aliases for modern tools
         environment.shellAliases = lib.mkIf cfg.modernUnix {
           ls = "eza";
           ll = "eza -l";
           la = "eza -la";
           cat = "bat";
           find = "fd";
           cd = "z";
         };
       };
     }
