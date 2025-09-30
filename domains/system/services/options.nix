# domains/system/services/options.nix
#
# Consolidated options for system services subdomain
# Charter-compliant: ALL services options defined here

{ lib, config, ... }:

{
  #============================================================================
  # BEHAVIOR OPTIONS (Input devices & audio)
  #============================================================================
  options.hwc.system.services.behavior = {
    enable = lib.mkEnableOption "system input behavior and audio configuration";

    keyboard = {
      enable = lib.mkEnableOption "universal keyboard mapping";
      universalFunctionKeys = lib.mkEnableOption "standardize F-keys across all keyboards";
    };

    mouse = {
      enable = lib.mkEnableOption "universal mouse configuration";
    };

    touchpad = {
      enable = lib.mkEnableOption "universal touchpad configuration";
    };

    audio = {
      enable = lib.mkEnableOption "PipeWire audio system";
    };
  };

  #============================================================================
  # SESSION OPTIONS (Sudo, login manager, lingering)
  #============================================================================
  options.hwc.system.services.session = {
    enable = lib.mkEnableOption "User session management (sudo, greetd, lingering)";

    sudo = {
      enable = lib.mkEnableOption "Configure sudo (wheel policy, optional extra rules)";

      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether members of wheel must enter a password for sudo";
      };

      enableExtraRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable extra NOPASSWD rules for specific users";
      };

      extraUsers = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to grant NOPASSWD sudo to (when enableExtraRules = true)";
      };
    };

    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Default user for autologin (if enabled)";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command executed after login";
      };

      autoLogin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically log in defaultUser into defaultCommand";
      };

      showTime = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show time in tuigreet";
      };

      greeterExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "--remember" "--remember-user-session" "--asterisks" ];
        description = "Additional tuigreet CLI arguments";
      };
    };

    linger = {
      enable = lib.mkEnableOption "Enable lingering for selected users (keeps user systemd running without login)";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to enable linger for (so user timers/services run when logged out)";
      };
    };
  };

  #============================================================================
  # SAMBA OPTIONS
  #============================================================================
  options.hwc.infrastructure.samba = {
    enable = lib.mkEnableOption "Samba file sharing with modern Windows compatibility";

    workgroup = lib.mkOption {
      type = lib.types.str;
      default = "WORKGROUP";
      description = "SMB workgroup name";
    };

    serverString = lib.mkOption {
      type = lib.types.str;
      default = "Samba on ${config.networking.hostName}";
      description = "Server description string";
    };

    security = lib.mkOption {
      type = lib.types.enum [ "user" "ads" "domain" ];
      default = "user";
      description = "Samba security model";
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.path;
            description = "Path to shared directory";
          };

          browseable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether share appears in browse lists";
          };

          readOnly = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether share is read-only";
          };

          guestAccess = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Allow guest access to share";
          };

          extraSettings = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional share-specific settings";
          };
        };
      });
      default = {};
      description = "Samba share configurations";
    };

    enableSketchupShare = lib.mkEnableOption "SketchUp VM share at /opt/sketchup/vm/shared";
  };

  #============================================================================
  # NETWORKING OPTIONS (SSH, Tailscale, Firewall, DNS)
  #============================================================================
  options.hwc.networking = {
    enable = lib.mkEnableOption "HWC networking configuration";

    ssh = {
      enable = lib.mkEnableOption "SSH server configuration";

      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "SSH server port";
      };

      allowRootLogin = lib.mkOption {
        type = lib.types.enum [ "yes" "no" "prohibit-password" ];
        default = "no";
        description = "Allow root login via SSH";
      };

      passwordAuthentication = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow password authentication";
      };

      x11Forwarding = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable X11 forwarding for GUI applications";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open SSH port in firewall";
      };
    };

    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN mesh networking";

      permitCertUid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User that can access Tailscale certificates (e.g., 'caddy')";
      };

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to Tailscale auth key file";
      };

      extraUpFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra flags for tailscale up command";
      };
    };

    networkManager = {
      enable = lib.mkEnableOption "NetworkManager for network management";

      dns = lib.mkOption {
        type = lib.types.enum [ "systemd-resolved" "dnsmasq" "none" ];
        default = "systemd-resolved";
        description = "DNS backend for NetworkManager";
      };

      wifi = {
        backend = lib.mkOption {
          type = lib.types.enum [ "wpa_supplicant" "iwd" ];
          default = "wpa_supplicant";
          description = "WiFi backend";
        };

        powersave = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable WiFi power saving";
        };
      };
    };

    firewall = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable firewall";
      };

      strict = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use strict firewall rules (deny by default)";
      };

      allowPing = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow ICMP ping requests";
      };

      logRefusedConnections = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Log refused connections";
      };

      services = {
        ssh = lib.mkOption {
          type = lib.types.bool;
          default = config.hwc.networking.ssh.enable;
          description = "Allow SSH traffic";
        };

        web = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow HTTP/HTTPS traffic (80, 443)";
        };

        tailscale = lib.mkOption {
          type = lib.types.bool;
          default = config.hwc.networking.tailscale.enable;
          description = "Allow Tailscale traffic";
        };
      };

      extraTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional TCP ports to open";
      };

      extraUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional UDP ports to open";
      };

      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Network interfaces to trust completely";
      };
    };

    dns = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure DNS resolution";
      };

      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "1.1.1.1" "8.8.8.8" ];
        description = "DNS servers to use";
      };

      fallbackServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "9.9.9.9" "149.112.112.112" ];
        description = "Fallback DNS servers";
      };
    };
  };
}