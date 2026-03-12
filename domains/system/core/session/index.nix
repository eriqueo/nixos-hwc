{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.core.session;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.core.session = {
    # Master toggle
    enable = lib.mkEnableOption "Enable user session management (sudo, login manager, lingering)";

    # --- Sudo Sub-Module ---
    sudo = {
      enable = lib.mkEnableOption "Enable sudo configuration";

      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false; # Single-user workstation default
        description = "Whether members of the 'wheel' group must enter a password for sudo.";
      };

      extraRules = lib.mkOption {
        type = with lib.types; listOf attrs;
        default = [];
        example = [
          { users = [ "eric" ]; commands = [ { command = "/run/current-system/sw/bin/podman"; options = [ "NOPASSWD" ]; } ]; }
        ];
        description = "Additional sudo rules for specific commands without password.";
      };
    };

    # --- Login Manager Sub-Module ---
    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      autoLoginUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "eric";
        description = "User to automatically log in. Set null to disable autologin.";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command (e.g. 'Hyprland', 'gnome', 'plasma').";
      };
    };

    # --- Linger Sub-Module ---
    linger = {
      enable = lib.mkEnableOption "Enable user lingering";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
        example = [ "eric" ];
        description = "List of users to enable linger for.";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SUDO CONFIGURATION
    #=========================================================================

    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      wheelNeedsPassword = cfg.sudo.wheelNeedsPassword;
      extraRules = cfg.sudo.extraRules;
    };

    #=========================================================================
    # LOGIN MANAGER (greetd + tuigreet)
    #=========================================================================

    services.greetd = lib.mkIf cfg.loginManager.enable {
      enable = true;

      # Wrap Hyprland in a small starter script that:
      #  - guarantees a session D-Bus
      #  - exports safe Wayland/NVIDIA env vars for hybrid laptops
      #  - execs Hyprland by absolute path
      #
      # Notes:
      #  - The NVIDIA exports are safe on Intel (ignored if NVIDIA isn't active)
      #  - Remove WLR_NO_HARDWARE_CURSORS if you never see cursor glitches
      #
      settings =
        let
          hyprStart = pkgs.writeShellScript "start-hyprland-session" ''
            export XDG_SESSION_TYPE=wayland
            export XDG_CURRENT_DESKTOP=Hyprland
            export WLR_RENDERER=vulkan
            # Helps on some NVIDIA systems; harmless elsewhere
            export WLR_NO_HARDWARE_CURSORS=1

            # NVIDIA PRIME offload hints (ignored if not applicable)
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __VK_LAYER_NV_optimus=NVIDIA_only
            export __GLX_VENDOR_LIBRARY_NAME=nvidia

            # Optional VA-API on NVIDIA; harmless if driver not present
            export LIBVA_DRIVER_NAME=nvidia

            # Keep logs useful
            export HYPRLAND_LOG_WLR=1

            exec ${pkgs.dbus}/bin/dbus-run-session ${pkgs.hyprland}/bin/Hyprland
          '';
        in
        {
          default_session = {
            user = "greeter";
            command =
              let
                args = "--time --remember --remember-user-session --asterisks";
              in
              "${pkgs.tuigreet}/bin/tuigreet ${args} --cmd ${hyprStart}";
          };
        }
        // lib.optionalAttrs (cfg.loginManager.autoLoginUser != null) {
          initial_session = {
            user = cfg.loginManager.autoLoginUser;
            command = "${hyprStart}";
          };
        };
    };

    # Keep these to avoid display-manager conflicts (NixOS 24.11+ uses services.displayManager)
    services.displayManager.gdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    #=========================================================================
    # USER LINGERING
    #=========================================================================

    users.users = lib.mkIf cfg.linger.enable (
      lib.genAttrs cfg.linger.users (_: { linger = true; })
    );

    #=========================================================================
    # CO-LOCATED PACKAGES
    #=========================================================================

    # Ensure tuigreet available
    environment.systemPackages = lib.mkIf cfg.loginManager.enable [ pkgs.tuigreet ];

    #=========================================================================
    # VALIDATION
    #=========================================================================

    assertions = [
      {
        assertion = (cfg.loginManager.autoLoginUser == null)
                 || (lib.hasAttr cfg.loginManager.autoLoginUser config.users.users);
        message = "Login manager: autoLoginUser '${cfg.loginManager.autoLoginUser}' is not a defined user.";
      }
      {
        assertion = (!cfg.linger.enable)
                 || (lib.all (u: lib.hasAttr u config.users.users) cfg.linger.users);
        message = "Lingering: one or more users in the linger list are not defined users.";
      }
    ];
  };

}
