{
  config,
  lib,
  pkgs,
  ...
}:

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
        default = [ ];
        example = [
          {
            users = [ "eric" ];
            commands = [
              {
                command = "/run/current-system/sw/bin/podman";
                options = [ "NOPASSWD" ];
              }
            ];
          }
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

      preferredDrmDevice = {
        enable = lib.mkEnableOption "runtime-resolved compositor DRM device preference";

        pciAddress = lib.mkOption {
          type = lib.types.strMatching "[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-7]";
          default = "0000:00:02.0";
          description = "PCI address whose connected DRM card should be preferred by Aquamarine.";
        };

        vendorId = lib.mkOption {
          type = lib.types.strMatching "0x[0-9a-fA-F]{4}";
          default = "0x8086";
          description = "Expected PCI vendor ID; prevents a PCI topology change from selecting the wrong GPU.";
        };

        fallbackWindowSeconds = lib.mkOption {
          type = lib.types.ints.between 1 60;
          default = 15;
          description = "Retry unpinned once when a pinned compositor exits nonzero inside this startup window.";
        };
      };
    };

    # --- Linger Sub-Module ---
    linger = {
      enable = lib.mkEnableOption "Enable user lingering";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
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
          resolveDrmDevice = pkgs.writeShellScript "resolve-preferred-drm-device" ''
            set -eu

            sys_root="''${1:-/sys}"
            dev_root="''${2:-/dev}"
            pci_address="''${3:-${cfg.loginManager.preferredDrmDevice.pciAddress}}"
            vendor_id="''${4:-${cfg.loginManager.preferredDrmDevice.vendorId}}"
            candidates=""
            count=0

            for card in "$sys_root"/class/drm/card[0-9]*; do
              [ -d "$card" ] || continue
              card_name=$(${pkgs.coreutils}/bin/basename "$card")
              device_path=$(${pkgs.coreutils}/bin/readlink -f "$card/device") || continue
              [ "$(${pkgs.coreutils}/bin/basename "$device_path")" = "$pci_address" ] || continue
              [ -r "$card/device/vendor" ] || continue
              [ "$(${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]' < "$card/device/vendor")" = "$(printf '%s' "$vendor_id" | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]')" ] || continue
              [ -c "$dev_root/dri/$card_name" ] || continue

              connector_count=0
              for connector in "$sys_root"/class/drm/"$card_name"-*; do
                [ -e "$connector" ] && connector_count=$((connector_count + 1))
              done
              [ "$connector_count" -gt 0 ] || continue

              candidates="$dev_root/dri/$card_name"
              count=$((count + 1))
            done

            if [ "$count" -ne 1 ]; then
              echo "HWC_POWER_DRM_RESOLUTION_FAILED code=drm_candidate_count count=$count pci=$pci_address vendor=$vendor_id" >&2
              exit 65
            fi

            printf '%s\n' "$candidates"
          '';

          hyprStart = pkgs.writeShellScript "start-hyprland-session" ''
            export XDG_SESSION_TYPE=wayland
            export XDG_CURRENT_DESKTOP=Hyprland
            export WLR_RENDERER=vulkan
            export WLR_NO_HARDWARE_CURSORS=1
            export HYPRLAND_LOG_WLR=1

            # Aquamarine accepts colon-delimited DRM paths and canonicalizes
            # symlinks, but a prior static by-path preference still aborted
            # Hyprland 0.56 during startup. Resolve the real card node from a
            # stable PCI identity at login, and only export it after verifying
            # vendor, connector presence, a character device, and uniqueness.
            # Resolution failure deliberately leaves normal enumeration intact.

            # NVIDIA PRIME env (__NV_PRIME_RENDER_OFFLOAD, __GLX_VENDOR_LIBRARY_NAME,
            # __VK_LAYER_NV_optimus, LIBVA_DRIVER_NAME=nvidia) is intentionally NOT
            # exported here. These vars are not "ignored if not applicable" — they
            # actively route libglvnd/libva onto the NVIDIA EGL/VA-API vendors
            # regardless of which GPU is rendering. On a hybrid laptop (Intel
            # iGPU primary, NVIDIA via PRIME offload), exporting them at session
            # start poisons Hyprland and every child process with mixed Mesa/
            # NVIDIA EGL state, causing the compositor to crash on cross-vendor
            # DMA-BUF imports (WebGL contexts, GL-accelerated clients).
            #
            # NVIDIA offload is per-process. Use one of:
            #   gpu-launch <app>      — reads the user-runtime launch policy
            #   blender-offload       — Blender-specific NVIDIA dGPU launcher
            # Both in domains/system/gpu/index.nix.

            # Join the systemd user bus instead of spawning a private one.
            # `dbus-run-session` was creating a throwaway session bus
            # (/tmp/dbus-XXX) for Hyprland and every app it launches, while
            # `systemd --user` services (pass-secret-service, the
            # xdg-desktop-portal-* units, waybar) live on the user bus at
            # $XDG_RUNTIME_DIR/bus. That split meant GUI apps could not see
            # org.freedesktop.secrets: Electron/Cowork's launcher probes
            # `NameHasOwner org.freedesktop.secrets`, got false on the private
            # bus, fell back to `--password-store=basic`, and Electron
            # safeStorage then reported "encryption not available" — so Cowork
            # could not persist its project allowlist and every project
            # create/import failed ("Failed to create project" → "Project not
            # found"). Pointing at the user bus (already populated:
            # `systemctl --user show-environment` shows DBUS_SESSION_BUS_ADDRESS,
            # WAYLAND_DISPLAY, XDG_CURRENT_DESKTOP) unifies the session so the
            # Secret Service and portals resolve. The user bus exists pre-login
            # via user lingering; the fallback covers an unset XDG_RUNTIME_DIR.
            export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/bus"

            drm_pinned=0
            ${lib.optionalString cfg.loginManager.preferredDrmDevice.enable ''
              if resolved_drm=$(${resolveDrmDevice}); then
                export AQ_DRM_DEVICES="$resolved_drm"
                drm_pinned=1
              else
                echo "HWC_POWER_DRM_FALLBACK code=resolution_failed action=normal_enumeration" >&2
              fi
            ''}

            started_at=$(${pkgs.coreutils}/bin/date +%s)
            ${pkgs.hyprland}/bin/start-hyprland
            status=$?

            elapsed=$(($(${pkgs.coreutils}/bin/date +%s) - started_at))
            if [ "$drm_pinned" -eq 1 ] && [ "$status" -ne 0 ] && [ "$elapsed" -lt ${toString cfg.loginManager.preferredDrmDevice.fallbackWindowSeconds} ]; then
              echo "HWC_POWER_DRM_FALLBACK code=pinned_start_failed status=$status elapsed=$elapsed action=retry_unpinned" >&2
              unset AQ_DRM_DEVICES
              exec ${pkgs.hyprland}/bin/start-hyprland
            fi

            exit "$status"
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
          default_session =
            if (cfg.loginManager.autoLoginUser != null) then
              {
                user = cfg.loginManager.autoLoginUser;
                command = "${hyprAutoRestart}";
              }
            else
              {
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
      lib.genAttrs cfg.linger.users (_: {
        linger = true;
      })
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
        assertion =
          (cfg.loginManager.autoLoginUser == null)
          || (lib.hasAttr cfg.loginManager.autoLoginUser config.users.users);
        message = "Login manager: autoLoginUser '${cfg.loginManager.autoLoginUser}' is not a defined user.";
      }
      {
        assertion =
          (!cfg.linger.enable) || (lib.all (u: lib.hasAttr u config.users.users) cfg.linger.users);
        message = "Lingering: one or more users in the linger list are not defined users.";
      }
    ];
  };

}
