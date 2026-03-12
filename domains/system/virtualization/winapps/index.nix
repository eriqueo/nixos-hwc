# domains/system/virtualization/winapps/index.nix
#
# WinApps - Windows applications integration via RDP
# Provides seamless Windows application integration for Linux desktop.
#
# USAGE:
#   hwc.system.virtualization.winapps.enable = true;
#   hwc.system.virtualization.winapps.rdpSettings.user = "eric";
#   hwc.system.virtualization.winapps.rdpSettings.ip = "192.168.122.10";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.virtualization.winapps;
  virt = config.hwc.system.virtualization;
  t = lib.types;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.virtualization.winapps = {
    enable = lib.mkEnableOption "WinApps - Windows applications integration via RDP";

    rdpSettings = {
      vmName = lib.mkOption {
        type = t.str;
        default = "RDPWindows";
        description = "Name of the Windows VM (must match libvirt domain name)";
      };

      ip = lib.mkOption {
        type = t.str;
        default = "192.168.122.10";
        description = "IP address of the Windows VM";
      };

      user = lib.mkOption {
        type = t.str;
        default = "";
        description = "Windows username for RDP connection";
      };

      scale = lib.mkOption {
        type = t.int;
        default = 100;
        description = "Display scale percentage";
      };

      flags = lib.mkOption {
        type = t.str;
        default = "/cert-ignore /dynamic-resolution /audio-mode:1";
        description = "Additional FreeRDP flags";
      };
    };

    multiMonitor = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable multi-monitor support";
    };

    debug = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable debug mode for troubleshooting";
    };

    autoStart = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Automatically start Windows VM on system boot";
    };

    autoInstall = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Automatically install WinApps on first activation";
    };

    monitorService = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable systemd service to monitor VM health";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================

  config = lib.mkIf cfg.enable {
    # Ensure git is available for WinApps installation
    environment.systemPackages = with pkgs; [
      git
      xdg-utils
      # WinApps management scripts
      (pkgs.writeShellScriptBin "winapps-setup" (builtins.readFile ./parts/install-winapps.sh))
      (pkgs.writeShellScriptBin "winapps-vm" (builtins.readFile ./parts/vm-manager.sh))
      (pkgs.writeShellScriptBin "winapps-helper" (builtins.readFile ./parts/winapps-helper.sh))
    ];

    # Create WinApps configuration directory and files
    system.activationScripts.winapps-setup = {
      deps = [ "users" ];
      text = ''
        # Create WinApps config directory for primary user
        primary_user=$(ls /home | head -1)
        if [ -n "$primary_user" ] && [ -d "/home/$primary_user" ]; then
          config_dir="/home/$primary_user/.config/winapps"
          mkdir -p "$config_dir"

          # Generate WinApps configuration file
          cat > "$config_dir/winapps.conf" << 'EOF'
# RDP Connection Settings
RDP_USER="${cfg.rdpSettings.user}"
RDP_PASS=""  # Password should be set manually for security
RDP_DOMAIN=""
RDP_IP="${cfg.rdpSettings.ip}"

# Display Settings
RDP_SCALE=${toString cfg.rdpSettings.scale}
RDP_FLAGS="${cfg.rdpSettings.flags}"

# VM Settings
MULTIMON="${if cfg.multiMonitor then "true" else "false"}"
DEBUG="${if cfg.debug then "true" else "false"}"
EOF

          # Set proper ownership
          chown -R $primary_user:users "$config_dir"
          chmod 600 "$config_dir/winapps.conf"
        fi

        # Auto-install WinApps if enabled
        ${lib.optionalString cfg.autoInstall ''
          if [ -n "$primary_user" ] && [ -d "/home/$primary_user" ]; then
            # Check if WinApps is already installed
            if [ ! -f "/home/$primary_user/.local/bin/winapps" ] && [ ! -f "/home/$primary_user/03-tech/local-storage/winapps/winapps" ]; then
              echo "Auto-installing WinApps..."
              sudo -u $primary_user bash -c 'winapps-setup' || echo "WinApps auto-installation failed"
            fi
          fi
        ''}
      '';
    };

    # Optional VM auto-start service
    systemd.services.winapps-vm-autostart = lib.mkIf cfg.autoStart {
      description = "Auto-start WinApps Windows VM";
      after = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = "${pkgs.libvirt}/bin/virsh start ${cfg.rdpSettings.vmName}";
        ExecStop = "${pkgs.libvirt}/bin/virsh shutdown ${cfg.rdpSettings.vmName}";
      };
    };

    # Optional VM monitoring service
    systemd.services.winapps-monitor = lib.mkIf cfg.monitorService {
      description = "Monitor WinApps Windows VM health";
      after = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 30;
        User = "root";
        ExecStart = pkgs.writeShellScript "winapps-monitor" ''
          #!/bin/bash
          while true; do
            # Check if VM exists and should be monitored
            if ${pkgs.libvirt}/bin/virsh list --all | grep -q "${cfg.rdpSettings.vmName}"; then
              state=$(${pkgs.libvirt}/bin/virsh domstate "${cfg.rdpSettings.vmName}" 2>/dev/null || echo "error")

              case "$state" in
                "running")
                  # VM is running, check RDP connectivity
                  if ! timeout 5 bash -c "</dev/tcp/${cfg.rdpSettings.ip}/3389" 2>/dev/null; then
                    echo "Warning: RDP port not accessible on ${cfg.rdpSettings.ip}"
                  fi
                  ;;
                "shut off")
                  echo "VM ${cfg.rdpSettings.vmName} is shut off"
                  ;;
                "error")
                  echo "Error querying VM state"
                  ;;
              esac
            else
              echo "VM ${cfg.rdpSettings.vmName} not found"
            fi

            sleep 60
          done
        '';
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================

    warnings = lib.optionals (cfg.rdpSettings.user == "") [
      "WinApps RDP user not configured. Set hwc.system.virtualization.winapps.rdpSettings.user in your machine config."
    ];

    assertions = [
      {
        assertion = virt.enable;
        message = "WinApps requires virtualization to be enabled (hwc.system.virtualization.enable = true)";
      }
      {
        assertion = cfg.rdpSettings.ip != "";
        message = "WinApps requires RDP IP address to be configured";
      }
    ];
  };

}
