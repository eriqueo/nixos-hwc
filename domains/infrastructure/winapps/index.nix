# domains/infrastructure/winapps/index.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.winapps;
  virt = config.hwc.infrastructure.virtualization;
in
{
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================

  config = lib.mkIf cfg.enable {
    # Ensure git is available for WinApps installation
    environment.systemPackages = with pkgs; [
      git
      xdg-utils
    ];

    # Enable FreeRDP program for system-wide configuration
    programs.xfreeRDP.enable = true;

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
      '';
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================

  config.warnings = lib.optionals cfg.enable [
    (lib.mkIf (cfg.rdpSettings.user == "")
      "WinApps RDP user not configured. Set hwc.infrastructure.winapps.rdpSettings.user in your machine config.")
  ];

  config.assertions = [
    {
      assertion = !cfg.enable || virt.enable;
      message = "WinApps requires virtualization to be enabled (hwc.infrastructure.virtualization.enable = true)";
    }
    {
      assertion = !cfg.enable || (cfg.rdpSettings.ip != "");
      message = "WinApps requires RDP IP address to be configured";
    }
  ];
}