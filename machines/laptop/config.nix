# nixos-hwc/machines/laptop/config.nix
#
# MACHINE: HWC-LAPTOP
# Declares machine identity and composes profiles; states hardware reality.
# Follows the refactored system domain architecture.

{ config, lib, pkgs, modulesPath, ... }:

let
  user = config.hwc.system.users.user.name;

  # Generic USB drive auto-mount with user-accessible permissions.
  # Handles NTFS, exFAT, and FAT32. Skips drives already declared in
  # /etc/fstab (e.g., the Seagate via fileSystems) so there's no conflict.
  usbAutoMount = pkgs.writeShellScript "usb-automount" ''
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -z "''${1:-}" ]] && exit 1
    DEVICE="/dev/$1"

    # Skip drives managed declaratively (UUID present in /etc/fstab)
    UUID=$(${pkgs.util-linux}/bin/blkid -o value -s UUID "$DEVICE" 2>/dev/null || true)
    [[ -n "$UUID" ]] && grep -qiF "$UUID" /etc/fstab && exit 0

    FSTYPE=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)
    [[ -z "$FSTYPE" ]] && exit 0

    LABEL=$(${pkgs.util-linux}/bin/blkid -o value -s LABEL "$DEVICE" 2>/dev/null \
      | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '_')
    # Strip leading dots/underscores — a label of ".." would otherwise resolve
    # to /mnt/.. = / and mount -t ntfs3 $DEVICE / as root. Not great.
    LABEL="''${LABEL##*([._])}"
    [[ -z "$LABEL" ]] && LABEL="usb-$(basename "$DEVICE")"

    # Check the device itself, not the mount point — avoids false "already mounted"
    # if two drives happen to share a label.
    ${pkgs.util-linux}/bin/findmnt -n "$DEVICE" >/dev/null 2>&1 && exit 0

    MOUNT="/mnt/$LABEL"
    mkdir -p "$MOUNT"
    # Clean up the empty dir if mount fails so we don't leave stray /mnt/* entries.
    trap '${pkgs.util-linux}/bin/mountpoint -q "$MOUNT" || rmdir "$MOUNT" 2>/dev/null || true' EXIT

    case "$FSTYPE" in
      ntfs|ntfs3)
        ${pkgs.util-linux}/bin/mount -t ntfs3 \
          -o uid=1000,gid=100,dmask=0000,fmask=0000,force,iocharset=utf8 \
          "$DEVICE" "$MOUNT"
        # NTFS Windows ACLs can map dirs to root — fix so Yazi can delete
        ${pkgs.findutils}/bin/find "$MOUNT" -maxdepth 1 -not -user ${user} \
          -exec ${pkgs.coreutils}/bin/chown -R ${user}:users {} + 2>/dev/null || true
        ;;
      exfat)
        ${pkgs.util-linux}/bin/mount -t exfat \
          -o uid=1000,gid=100,dmask=0000,fmask=0000 \
          "$DEVICE" "$MOUNT"
        ;;
      vfat|fat32|fat)
        ${pkgs.util-linux}/bin/mount -t vfat \
          -o uid=1000,gid=100,dmask=0000,fmask=0000,codepage=437,iocharset=utf8 \
          "$DEVICE" "$MOUNT"
        ;;
    esac
  '';

  usbAutoUnmount = pkgs.writeShellScript "usb-autounmount" ''
    #!/usr/bin/env bash
    DEVICE="/dev/$1"
    TARGET=$(${pkgs.util-linux}/bin/findmnt -n -o TARGET "$DEVICE" 2>/dev/null || true)
    [[ -n "$TARGET" ]] && ${pkgs.util-linux}/bin/umount "$TARGET" 2>/dev/null || true
  '';
in

{
  ##############################################################################
  ##  MACHINE: HWC-LAPTOP
  ##  This file defines the unique properties and profile composition for the
  ##  hwc-laptop machine.
  ##############################################################################

  #============================================================================
  # IMPORTS - Compose the machine from profiles and hardware definitions
  #============================================================================
  imports = [
    # Hardware-specific definitions for this machine (e.g., filesystems).
    ./hardware.nix
    "${modulesPath}/hardware/cpu/intel-npu.nix"

    # Profiles — core (system/paths/secrets) + session (GUI/audio/HM)
    ../../profiles/core.nix
    ../../profiles/session.nix
    # Machine-specific HM overrides imported via home-manager.users.eric below

    # Domains — laptop-specific capabilities
    ../../domains/ai/index.nix
    ../../domains/automation/index.nix
    ../../domains/notifications/index.nix
    ../../domains/networking/index.nix
  ];
  nix.settings = {
    substituters = [
      "https://cache.nixos.org/"
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
  # Blender 3D modeling with GPU rendering support (configured in profiles/home.nix)
  # External presets stored in ~/500_media/540_blender

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "button.lid_init_state=open" ];
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

  # Hibernation disabled (using zram swap for better performance)
  # boot.resumeDevice = "/dev/disk/by-uuid/0ebc1df3-65ec-4125-9e73-2f88f7137dc7";
  # boot.kernelParams = [ "resume_offset=0" ];

  # Power management for laptop
  powerManagement.enable = true;
  services.logind = {
    # All settings are now consolidated under the 'settings' attribute set.
    settings = {
      Login = {
        # Base: suspend on lid close (inhibitor service blocks at runtime)
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        # Suspend on power button (hibernation disabled with zram)
        HandlePowerKey = "suspend";
        # Disable idle suspend (laptop left running for extended period)
        IdleAction = "ignore";
        # IdleActionSec = "30min";  # Disabled - no idle action configured
      };
    };
  };

  # Foreground-aware scheduling for hybrid P/E cores (Auto-VIP)
  services.system76-scheduler.enable = true;

  #============================================================================
  # === [profiles/system.nix] Orchestration ====================================
  #============================================================================

  # --- System Services Configuration ---
  hwc.system.core.shell.enable = true;

  # BOM-PROOF LOGIN: Ensure 'il0wwlm?' always works for 'eric' and 'root' on laptop.
  # This makes the login screen independent of secret decryption.
  hwc.system.users.user.useSecrets = false;
  hwc.secrets.emergency = {
    hashedPassword = lib.mkForce "$6$McKMuWn2JliY4HR.$0pDd/FJPdbENIqCwXIMsXXEZcaLOriieUZlXEb0YxnqAUrJiZ05SIdVJVQ5BnR3TksU9DGoZcGBGzB5qiFT0b/";
    hashedPasswordFile = lib.mkForce null;
  };

  # Enable hardware services for keyboard remapping and audio.
  hwc.system.hardware = {
    enable = true;
    keyboard.enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    monitoring.enable = true;
    fanControl.enable = true;
    peripherals = {
      enable = true;
      avahi = true;  # Network printer discovery
      drivers = [ pkgs.brlaser pkgs.hplip ];  # HP and Brother drivers
    };
  };

  # Gotify notification system for laptop alerts
  # Per-app tokens: each service gets its own gotify application token
  hwc.notifications.send.gotify = {
    enable = true;
    serverUrl = "https://hwc.ocelot-wahoo.ts.net:2586";  # Self-hosted gotify via Tailscale HTTPS
    defaultTokenFile = config.hwc.secrets.api."gotify-token-laptop" or null;
    defaultPriority = 5;  # Normal priority for laptop
    hostTag = true;       # Prepends "[host: hwc-laptop]" to messages
  };

  # Rsync backup DISABLED - consolidated to Borg
  # TODO: Enable Borg on laptop when backup drive is mounted
  hwc.data.backup.enable = false;

  # Enable the declarative VPN service using the official CLI.
  hwc.networking.vpn.protonvpn.enable = true;

  # Proton Mail Bridge managed by Home Manager user service (NOT system service)
  # hwc.home.mail.bridge.system.enable = false;  # Disabled in profile

  # Enable session management (greetd autologin, sudo, lingering).
  hwc.system.core.session = {
    enable = true;
    loginManager.enable = true;
    loginManager.autoLoginUser = "eric";
    sudo.enable = true;
    sudo.extraRules = [
      # Allow eric to start/stop ollama service without password (for waybar toggle)
      {
        users = [ "eric" ];
        commands = [
          { command = "/run/current-system/sw/bin/systemctl start podman-ollama.service"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl stop podman-ollama.service"; options = [ "NOPASSWD" ]; }
          # Performance mode: allow CPU governor changes
          { command = "/run/current-system/sw/bin/tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
    linger.enable = true;
    linger.users = [ "eric" ];
  };

  # --- Networking Configuration (Laptop: do NOT block boot on network) ---
  hwc.system.networking = {
    enable = true;
    networkManager.enable = true;

    # Laptop should not wait-online; Hyprland can start immediately.
    waitOnline.mode = "off";

    ssh.enable = true;            # Enable the SSH server.
    firewall.level = "strict";
    firewall.extraTcpPorts = [ 56037 ];
    firewall.extraUdpPorts = [ 56037 ];
    tailscale.enable = true;
    tailscale.extraUpFlags = [ "--accept-dns" ];
    nfs.client.enable = true;
  };

  # Syncthing — bidirectional home folder sync with hwc-server
  # Phase 1: service running, pair devices via GUI at http://localhost:8384
  # Phase 2: add device IDs + folder declarations for fully declarative config.
  # overrideDevices/Folders = false so GUI-paired state survives rebuilds during bootstrap.
  services.syncthing = {
    enable = true;
    user = "eric";
    dataDir = "/home/eric";
    openDefaultPorts = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      options.globalAnnounceEnabled = false;  # Tailscale only, no cloud relay
      devices."hwc-server" = {
        id = "5UCUDT4-CUUGX7U-F2XVLET-SE3QGCA-JRYGXK3-45MQOBP-SYMQZM7-O653IAA";
        addresses = [ "tcp://100.114.232.124:22000" ];  # Server Tailscale IP
      };
      folders = {
        "000_inbox"   = { path = "/home/eric/000_inbox";   devices = [ "hwc-server" ]; versioning.type = "staggered"; versioning.params.maxAge = "2592000"; };
        "100_hwc"     = { path = "/home/eric/100_hwc";     devices = [ "hwc-server" ]; versioning.type = "staggered"; versioning.params.maxAge = "2592000"; };
        "200_personal" = { path = "/home/eric/200_personal"; devices = [ "hwc-server" ]; versioning.type = "staggered"; versioning.params.maxAge = "2592000"; };
        "300_tech"    = { path = "/home/eric/300_tech";    devices = [ "hwc-server" ]; versioning.type = "staggered"; versioning.params.maxAge = "2592000"; };
      };
    };
  };

  # NFS mount: shared folder from server over Tailscale
  # Note: Literal path to avoid infinite recursion (fileSystems → paths → users → rpcbind → fileSystems)
  # Matches hwc.paths.user.shared default
  fileSystems."/home/eric/600_shared" = {
    device = "100.114.232.124:/home/eric/600_shared";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "soft"                          # Return errors instead of hanging if server unreachable
      "timeo=150"                     # 15-second timeout
      "x-systemd.automount"          # Mount on first access, not at boot
      "x-systemd.idle-timeout=600"   # Unmount after 10 min idle
      "noauto"                        # Don't mount at boot (automount handles it)
      "_netdev"                       # Network-dependent mount
    ];
  };

  # Seagate Backup Plus Drive — NTFS via ntfs3 kernel driver
  # UUID-based so it works regardless of device enumeration order (/dev/sdb vs /dev/sdc etc.)
  # x-systemd.automount: mounts on first access, not at boot (USB may not be present)
  # seagate-fixperms.service: chowns root-owned dirs after each mount so Yazi can delete
  fileSystems."/mnt/seagate" = {
    device = "/dev/disk/by-uuid/A802BE5102BE23EA";
    fsType = "ntfs3";
    options = [
      "uid=1000" "gid=100" "dmask=0000" "fmask=0000"
      "force" "iocharset=utf8"
      "noauto" "nofail" "x-systemd.automount" "x-systemd.device-timeout=5s"
    ];
  };

  systemd.tmpfiles.rules = [ "d /mnt/seagate 0755 root root -" ];

  systemd.services.seagate-fixperms = {
    description = "Fix Seagate NTFS directory ownership for user access";
    after = [ "mnt-seagate.mount" ];
    wantedBy = [ "mnt-seagate.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Only chown top-level dirs owned by root — sufficient for deletion (write on parent = delete child)
      # This persists to NTFS ACLs, so each run is faster as files gain eric ownership
      ExecStart = pkgs.writeShellScript "seagate-fixperms" ''
        ${pkgs.findutils}/bin/find /mnt/seagate -maxdepth 1 -not -user eric \
          -exec ${pkgs.coreutils}/bin/chown -R eric:users {} + 2>/dev/null || true
      '';
    };
  };

  #============================================================================
  # === [domains/system/hardware] Orchestration ================================
  #============================================================================

  # GPU capability (remains unchanged).
  hwc.system.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      containerRuntime = true;
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId  = "PCI:0:2:0";
    };
    powerManagement.smartToggle = true;
  };

  # Override NVIDIA power management defaults for proper suspend/resume
  # Fixes GPU state corruption in applications (like Kitty) after resume
  hardware.nvidia.powerManagement = {
    enable = true;           # Enable power management for suspend/resume
    finegrained = true;      # Pilot fine-grained PM for smoother offload
  };

  #============================================================================
  # VIRTUALIZATION
  #============================================================================
  # Libvirt/QEMU: make OVMF visible and avoid extra groups by using wheel sockets.
  virtualisation.libvirtd = {
    # Use wheel for socket perms so you don't need extra groups.
    extraConfig = ''
      unix_sock_group = "wheel"
      unix_sock_ro_perms = "0770"
      unix_sock_rw_perms = "0770"
    '';

    # OVMF is now available by default with QEMU
    qemu = {
      runAsRoot = lib.mkForce true;     # fixes OVMF metadata enumeration edge cases
      # OVMF images are now available by default in newer versions
    };
  };

  # Container engines enabled for Ollama AI workloads
  # Podman is required by hwc.ai.ollama module
  virtualisation.docker.enable = lib.mkForce false;  # Use podman, not docker

  # --- Declarative libvirt storage pool (requires NixVirt in flake) --
  # Commented out until NixVirt module is imported in flake.nix
  # virtualisation.libvirt.pools = [
  #   {
  #     name = "ISOs";
  #     present = true;
  #     type = "dir";
  #     target = {
  #       path = "${config.hwc.paths.hot}/ISOs";
  #       owner = "root";
  #       group = "root";
  #       mode  = "0755";
  #     };
  #     autostart = true;
  #   }
  # ];

  #============================================================================
  # === [profiles/home.nix] Orchestration =====================================
  #============================================================================
  # System-lane dependencies for home apps (co-located sys.nix files)
  # These are enabled separately because system evaluates before Home Manager
  hwc.system.apps.hyprland.enable = true;   # Startup script, helper scripts
  hwc.system.apps.waybar.enable = true;     # System dependency validation
  hwc.system.apps.chromium.enable = true;   # System integration (dconf, dbus)

  #============================================================================
  # === [profiles/security.nix] Orchestration =================================
  #============================================================================
  # (Profile-driven; nothing machine-specific added here.)

  #============================================================================
  # MISCELLANEOUS MACHINE-SPECIFIC SETTINGS
  #============================================================================

  # Storage paths (Charter v10.1 - hostname-based defaults with overrides)
  # Laptop defaults from paths.nix match most values, only override exceptions
  # Defaults: media.root=/home/eric/500_media, photos=.../510_pictures, backup=.../backup
  hwc.paths.hot.root = "/home/eric/500_media/hot";     # Override: laptop uses hot for active work
  hwc.paths.cold = "/home/eric/500_media/archive";     # Override: laptop archives locally

  # Machine-specific Home Manager overrides (HM-format, shared with standalone HM)
  home-manager.users.eric = { imports = [ ./home.nix ]; };

  #============================================================================
  # AI DOMAIN CONFIGURATION (Laptop)
  #============================================================================
  # Profile auto-detection: laptop (GPU: nvidia, RAM: 32GB < 16GB threshold)
  # Result: Conservative limits (2 cores, 4GB, 70°C warning, 80°C critical)
  hwc.ai = {
    # Profile selection (auto-detects laptop based on RAM/GPU)
    profiles.selected = "auto";

    # AI CLI tools (charter-search, ai-doc, ai-commit, ai-lint)
    tools = {
      enable = true;
      logging.enable = true;
    };

    # Ollama LLM service with profile-based defaults
    ollama = {
      enable = false;

      # Explicit model list (overrides profile defaults without mkForce)
      models = [
        "llama3.2:3b"          # 2.0GB, 10W, <10s - Documentation
        "deepseek-coder:6.7b"  # 4GB - Coding tasks
      ];

      # Override profile defaults for instant GPU inference
      # Profile would enable these for battery/thermal protection, but GPU can handle it
      idleShutdown.enable = false;
      thermalProtection.enable = false;

      # Profile automatically applies:
      # - resourceLimits: CPU=200%, Memory=4GB, Timeout=60s
      # - Models pulled on first boot
    };

    # AnythingLLM - Local AI assistant with file access
    # Access: http://localhost:3002
    anything-llm = {
      enable = false;
      # Mount ~/.nixos for AI to read/analyze NixOS configs
      workspace.nixosDir = true;
      # Default uses llama3.2:3b and nomic-embed-text from Ollama
    };

    # Local AI workflows disabled (can enable if needed)
    local-workflows.enable = false;
  };

  # Fix Ollama systemd service type (container sd-notify unreliable)
  systemd.services.podman-ollama.serviceConfig = lib.mkIf config.hwc.ai.ollama.enable {
    Type = lib.mkForce "forking";
    NotifyAccess = lib.mkForce "none";
  };

  # Static hosts for local services (remains unchanged).
  networking.hosts = {
    "100.114.232.124" = [
      "sonarr.local" "radarr.local" "prowlarr.local" "jellyfin.local"
      "lidarr.local" "qbittorrent.local" "grafana.local" "dashboard.local"
      "prometheus.local" "caddy.local" "server.local" "hwc.local"
    ];
  };

  #============================================================================
  # LOW-LEVEL SYSTEM OVERRIDES (Use Sparingly)
  #============================================================================
  # Power management: TLP handles thermal + power (thermald conflicts with TLP)
  services.tlp = {
    enable = true;
    settings = {
      # CPU performance settings
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # Battery charge thresholds (extends battery life)
      START_CHARGE_THRESH_BAT0 = 75;  # Start charging at 75%
      STOP_CHARGE_THRESH_BAT0 = 90;   # Stop charging at 90%

      # Add CPU energy/performance preferences
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_power";  # Changed from "performance" to reduce heat
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance-power";

      # Boost control (disable turbo on battery for cooler operation)
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # Power saving on battery
      WIFI_PWR_ON_BAT = "on";
      WOL_DISABLE = "Y";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;

      # SATA power management
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
    };
  };

  #============================================================================
  # PERFORMANCE TUNING (32GB RAM, dual NVMe system)
  #============================================================================
  # Disabled: thermald doesn't support Intel Core Ultra 9 185H (Meteor Lake)
  # TLP handles power/thermal management instead
  services.thermald.enable = false;
  boot.kernel.sysctl = {
    # Memory management for high-RAM system
    "vm.swappiness" = 100;              # Rarely use swap (have 32GB RAM + zram)
    "vm.vfs_cache_pressure" = 50;      # Keep file cache longer
    "vm.dirty_ratio" = 6;             # Allow more dirty memory before blocking
    "vm.dirty_background_ratio" = 3;  # Background writeback threshold

    # Network performance tuning
    "net.core.rmem_max" = 134217728;   # 128MB receive buffer
    "net.core.wmem_max" = 134217728;   # 128MB send buffer
    "net.ipv4.tcp_rmem" = "4096 87380 67108864";  # TCP receive buffer
    "net.ipv4.tcp_wmem" = "4096 65536 67108864";  # TCP send buffer
    "net.ipv4.tcp_congestion_control" = "bbr";    # Modern TCP congestion control

    # File descriptor limits for development workloads
    "fs.file-max" = 2097152;
    "fs.inotify.max_user_watches" = 524288;
  };

  # Device rules: kyber scheduler on NVMe + generic USB drive auto-mount
  services.udev.extraRules = lib.mkAfter ''
    ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"

    # Auto-mount external USB drives (NTFS/exFAT/FAT32) at /mnt/<label>
    # Drives in /etc/fstab (e.g., Seagate) are skipped — systemd handles those.
    ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="ntfs", \
      RUN+="${usbAutoMount} %k"
    ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="ntfs3", \
      RUN+="${usbAutoMount} %k"
    ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="exfat", \
      RUN+="${usbAutoMount} %k"
    ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="vfat", \
      RUN+="${usbAutoMount} %k"
    ACTION=="remove", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", \
      RUN+="${usbAutoUnmount} %k"
  '';

  # Intel NPU support (permissions, firmware, Level Zero loader)
  hardware.cpu.intel.npu.enable = true;

  # Add Level Zero and OpenCL runtime for NPU backend
  hardware.graphics.extraPackages = with pkgs; [
    level-zero
    intel-compute-runtime
  ];

  # Performance mode wrappers for CPU-intensive tasks
  # TODO: Consider moving to domains/system/services/performance/ module
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "perf-mode" ''
      #!/usr/bin/env bash
      # Temporarily switch to maximum CPU performance
      echo "⚡ Switching to Performance Mode..."
      echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
      ${pkgs.libnotify}/bin/notify-send "Performance Mode" "CPU governors set to maximum performance" -i cpu -u normal
      echo "CPU governors set to 'performance'"
      echo "Use 'balanced-mode' to restore power-efficient operation"
    '')

    (writeShellScriptBin "balanced-mode" ''
      #!/usr/bin/env bash
      # Restore balanced power-efficient mode
      echo "🔋 Restoring Balanced Mode..."
      echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
      ${pkgs.libnotify}/bin/notify-send "Balanced Mode" "CPU governors restored to power-efficient mode" -i cpu -u normal
      echo "CPU governors set to 'powersave' (dynamic scaling)"
    '')
  ];

  programs.dconf.enable = true;
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    glib glibc gtk3 pango cairo gdk-pixbuf atk
    nss nspr dbus expat libdrm mesa
    alsa-lib cups libpulseaudio
    libX11 libXcomposite libXcursor libXdamage libXext libXfixes
    libXi libXrandr libXrender libXtst libxcb libxscrnsaver
    at-spi2-atk at-spi2-core
    libgbm libxkbcommon
  ];

  # Allow password auth for SSH (same as server)
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;
}
