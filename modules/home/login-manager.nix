# nixos-hwc/modules/home/login-manager.nix
#
# Greetd Login Manager with TUI Greeter
# Provides minimal TTY login manager for Wayland desktop environments
#
# DEPENDENCIES:
#   Upstream: Desktop environment (Hyprland, Sway, etc.)
#   Upstream: config.hwc.users.primary (for initial session)
#
# USED BY:
#   Downstream: profiles/workstation.nix (enables for desktop environments)
#   Downstream: machines/laptop/config.nix (may override WM command)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/home/login-manager.nix
#
# USAGE:
#   hwc.home.loginManager.enable = true;
#   hwc.home.loginManager.defaultUser = "eric";
#   hwc.home.loginManager.defaultCommand = "Hyprland";
#   hwc.home.loginManager.autoLogin = true;  # Enable auto-login
#
# VALIDATION:
#   - Default user must exist
#   - Default command must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.loginManager;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.home.loginManager = {
    enable = lib.mkEnableOption "Greetd login manager with TUI greeter";
    
    # Default session settings
    defaultUser = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Default user for initial session";
    };
    
    defaultCommand = lib.mkOption {
      type = lib.types.str;
      default = "Hyprland";
      description = "Default window manager/desktop environment command";
    };
    
    # Auto-login settings
    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic login for default user";
    };
    
    # Greeter settings
    showTime = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show time in TUI greeter";
    };
    
    # Additional greeter options
    greeterExtraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional arguments to pass to tuigreet";
      example = [ "--asterisks" "--remember" "--remember-user-session" ];
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check default user exists
    assertions = [
      {
        assertion = config.users.users ? ${cfg.defaultUser};
        message = "Login manager default user '${cfg.defaultUser}' does not exist";
      }
    ];
    
    # Greetd service configuration
    services.greetd = {
      enable = true;
      settings = {
        # Default greeter session
        default_session = {
          user = "greeter";
          command = let
            timeArg = lib.optionalString cfg.showTime "--time";
            extraArgs = lib.concatStringsSep " " cfg.greeterExtraArgs;
            allArgs = lib.concatStringsSep " " (lib.filter (s: s != "") [ timeArg extraArgs ]);
          in "${pkgs.tuigreet}/bin/tuigreet ${allArgs} --cmd ${cfg.defaultCommand}";
        };
        
        # Auto-login session (if enabled)
      } // lib.optionalAttrs cfg.autoLogin {
        initial_session = {
          user = cfg.defaultUser;
          command = cfg.defaultCommand;
        };
      };
    };
    
    # Install greeter package
    environment.systemPackages = with pkgs; [
      tuigreet  # TUI greeter for greetd
    ];
    
    # Disable other display managers
    services.xserver.displayManager.gdm.enable = lib.mkForce false;
    services.xserver.displayManager.lightdm.enable = lib.mkForce false;
    services.xserver.displayManager.sddm.enable = lib.mkForce false;
  };
}