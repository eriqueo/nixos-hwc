# modules/system/users/options.nix
# User domain options - canonical interface for user management

{ lib, pkgs, ... }:

{
  options.hwc.system.users = {
    enable = lib.mkEnableOption "Enable HWC user management system";
    emergencyEnable = lib.mkEnableOption "Enable emergency root access during migration";

    user = {
      enable = lib.mkEnableOption "Eric user account configuration";

      name = lib.mkOption { 
        type = lib.types.str; 
        default = "eric"; 
        description = "Username for the primary user account";
      };
      
      description = lib.mkOption { 
        type = lib.types.str; 
        default = "Eric - Heartwood Craft"; 
        description = "Full name description for user account";
      };
      
      shell = lib.mkOption { 
        type = lib.types.package; 
        default = pkgs.zsh; 
        description = "Default shell for user account";
      };

      useSecrets = lib.mkOption { 
        type = lib.types.bool; 
        default = true; 
        description = "Use agenix secrets for user password management";
      };

      fallbackPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "il0wwlm?";
        description = "Fallback password if useSecrets is false. Must be set if useSecrets is false.";
      };
   
      groups = {
        basic = lib.mkEnableOption "basic user groups (wheel, networkmanager)";
        media = lib.mkEnableOption "media access groups (video, audio)";
        development = lib.mkEnableOption "development groups (docker, podman)";
        virtualization = lib.mkEnableOption "virtualization groups (libvirtd, kvm)";
        hardware = lib.mkEnableOption "hardware access groups (input, uucp)";
      };

      ssh = {
        enable = lib.mkEnableOption "SSH configuration for user";

        useSecrets = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Use agenix secrets for SSH keys";
        };

        fallbackKey = lib.mkOption {
          type = lib.types.str;
          default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICubgcmg6aBisQC+MWRC4RWOY8zIHEl42O7bTbzyCiGB eriqueo@proton.me";
          description = "Fallback SSH public key if secrets not available";
        };
      };

      environment = {
        enablePaths = lib.mkEnableOption "export HWC path environment variables";
        enableZsh = lib.mkEnableOption "ZSH system-level configuration";
      };
    };
  };
}