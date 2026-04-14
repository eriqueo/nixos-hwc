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

      rescueTTY = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Always keep a getty on tty2 so Ctrl+Alt+F2 gives a text login (lockout prevention).";
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

      settings =
        let
          hyprStart = pkgs.writeShellScript "start-hyprland-session" ''
            export XDG_SESSION_TYPE=wayland
            export XDG_CURRENT_DESKTOP=Hyprland
            export WLR_RENDERER=vulkan
            export WLR_NO_HARDWARE_CURSORS=1

            # NVIDIA PRIME offload hints (ignored if not applicable)
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __VK_LAYER_NV_optimus=NVIDIA_only
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export LIBVA_DRIVER_NAME=nvidia
            export HYPRLAND_LOG_WLR=1

            exec ${pkgs.dbus}/bin/dbus-run-session ${pkgs.hyprland}/bin/start-hyprland
          '';

          # Crash-resilient auto-login: restarts Hyprland after crash,
          # but falls back to tuigreet if it crashes 3 times in 60 seconds.
          hyprAutoRestart = pkgs.writeShellScript "hyprland-auto-restart" ''
            CRASH_LOG="/tmp/hyprland-crash-times"

            # Clean stale entries (older than 60 seconds)
            now=$(${pkgs.coreutils}/bin/date +%s)
            if [ -f "$CRASH_LOG" ]; then
              ${pkgs.coreutils}/bin/touch "$CRASH_LOG.tmp"
              while IFS= read -r ts; do
                if [ $((now - ts)) -lt 60 ]; then
                  echo "$ts" >> "$CRASH_LOG.tmp"
                fi
              done < "$CRASH_LOG"
              ${pkgs.coreutils}/bin/mv "$CRASH_LOG.tmp" "$CRASH_LOG"
            fi

            # Count recent crashes
            recent=0
            if [ -f "$CRASH_LOG" ]; then
              recent=$(${pkgs.coreutils}/bin/wc -l < "$CRASH_LOG")
            fi

            if [ "$recent" -ge 3 ]; then
              # Too many crashes — fall back to tuigreet so user isn't stuck in a loop
              echo "Hyprland crashed 3+ times in 60s, falling back to tuigreet" >&2
              ${pkgs.coreutils}/bin/rm -f "$CRASH_LOG"
              exec ${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --cmd ${hyprStart}
            fi

            # Record this attempt and launch Hyprland
            echo "$now" >> "$CRASH_LOG"
            exec ${hyprStart}
          '';
        in
        {
          # When autoLoginUser is set: default_session auto-restarts Hyprland
          # (with crash-loop protection that falls back to tuigreet).
          # When autoLoginUser is null: default_session is tuigreet as before.
          default_session = if (cfg.loginManager.autoLoginUser != null) then {
            user = cfg.loginManager.autoLoginUser;
            command = "${hyprAutoRestart}";
          } else {
            user = "greeter";
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --cmd ${hyprStart}";
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
    # RESCUE TTY — Always-available text console (lockout prevention)
    #=========================================================================
    # Ensures Ctrl+Alt+F2 always gives a working login prompt,
    # even if greetd/tuigreet/Hyprland are all broken.
    systemd.services."getty@tty2" = lib.mkIf (cfg.loginManager.enable && cfg.loginManager.rescueTTY) {
      enable = true;
      wantedBy = [ "getty.target" ];
      serviceConfig.Restart = "always";
    };

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
