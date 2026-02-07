{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.session;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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

    # Keep these to avoid display-manager conflicts
    # NixOS 24.05 uses services.xserver.displayManager, later versions use services.displayManager
    services.xserver.displayManager.gdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.xserver.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.xserver.displayManager.lightdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

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
