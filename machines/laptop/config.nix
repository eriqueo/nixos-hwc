# nixos-hwc/machines/laptop/config.nix
#
# MACHINE: HWC-LAPTOP
# Declares machine identity and composes profiles; states hardware reality.
# Follows the refactored system domain architecture.

{ config, lib, pkgs, modulesPath, ... }:

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

    # Roles (base, desktop) are supplied by the flake.nix machines table —
    # membership lives there, not here.

    # Domains — laptop-specific capabilities
    ../../domains/ai/index.nix
    ../../domains/automation/index.nix
    ../../domains/notifications/index.nix
    ../../domains/networking/index.nix
    ../../domains/server/native/ai/llama-cpp/index.nix # local llama.cpp (GPU LFM2-2.6B + embed); module reused in-place
  ];
  # CUDA binary cache comes from the gpu module (nvidia machines only).
  # Blender 3D modeling with GPU rendering support (configured in profiles/home-session.nix)
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
    settings = {
      Login = {
        # Lid close is handled by acpid + state file — NOT logind.
        # Using logind's handle-lid-switch (even via systemd-inhibit) triggers the
        # Sensel i2c_hid_acpi spurious "lid closed" bug, killing two-finger scroll.
        # acpid reads ACPI netlink events independently of logind/libinput.
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        # Suspend on power button (hibernation disabled with zram)
        HandlePowerKey = "suspend";
        # Disable idle suspend (laptop left running for extended period)
        IdleAction = "ignore";
      };
    };
  };

  # Lid-close suspend: handled here via acpid, NOT logind inhibitors.
  # State file: /run/user/1000/hwc-lid-ignore
  #   - absent   → lid close triggers suspend (default — nothing creates it)
  #   - present  → lid close does nothing
  # Toggle is managed by waybar-lid-toggle (writes/deletes the file — no D-Bus).
  services.acpid = {
    enable = true;
    handlers."hwc-lid-close" = {
      event = "button/lid LID close";
      action = ''
        STATE="/run/user/1000/hwc-lid-ignore"
        if [[ ! -f "$STATE" ]]; then
          ${pkgs.systemd}/bin/systemctl suspend
        fi
      '';
    };
  };

  # Foreground-aware scheduling for hybrid P/E cores (Auto-VIP)
  services.system76-scheduler.enable = true;

  #============================================================================
  # === [profiles/system.nix] Orchestration ====================================
  #============================================================================

  # --- System Services Configuration ---
  hwc.system.core.shell.enable = true;

  # FHS shim for the Claude Desktop Cowork port: its exec registry resolves host
  # tools (bash, git, curl, …) only from hardcoded /usr/bin + /bin paths, which
  # NixOS doesn't have — so Cowork's Bash/workspace "never boots". envfs maps
  # those paths onto the live PATH. See domains/home/apps/claude-desktop.
  hwc.system.core.envfs.enable = true;

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
    # Softer fan curve: extended silent zone + ~6°C-higher trip points so the
    # fan ramps later and gentler. Paired with turbo-boost-off-on-AC below,
    # peak temps stay low enough that the fan mostly sits at level 0-1.
    # Firmware emergency handoff at 90°C keeps it well clear of Tjmax (~100°C).
    fanControl.levels = [
      [ 0             0   60 ]   # Silent zone (was 55)
      [ 1            55   68 ]   # Gentle ramp
      [ 2            63   74 ]   # Gradual increase
      [ 3            70   80 ]   # Medium cooling
      [ 4            76   86 ]   # Higher cooling
      [ 5            82   92 ]   # Maximum manual control
      [ "level auto" 90 32767 ]  # Emergency firmware handoff
    ];
    peripherals = {
      enable = true;
      avahi = true;  # Network printer discovery
      drivers = [ pkgs.brlaser pkgs.hplip ];  # HP and Brother drivers
    };
  };

  # Rsync backup DISABLED - consolidated to Borg
  # TODO: Enable Borg on laptop when backup drive is mounted
  hwc.data.backup.enable = false;

  # Declarative ProtonVPN via WireGuard.
  # Peer values come from a config downloaded at account.protonvpn.com/downloads.
  # Private key lives in agenix secret `vpn-wireguard-private-key`.
  hwc.networking.vpn.enable = true;
  hwc.networking.vpn.protonvpn = {
    enable = false;                         # TEMP: re-enable after filling in WG values below
    address = [ "10.2.0.2/32" ];          # FILL IN: [Interface] Address from .conf
    peer.publicKey = "";                    # FILL IN: [Peer] PublicKey from .conf
    peer.endpoint  = "";                    # FILL IN: [Peer] Endpoint from .conf, e.g. "198.51.100.42:51820"
  };

  # Proton Mail Bridge managed by Home Manager user service (NOT system service)
  # hwc.home.mail.bridge.system.enable = false;  # Disabled in profile

  # Enable session management (greetd autologin, sudo, lingering).
  hwc.system.core.session = {
    enable = true;
    loginManager.enable = true;
    loginManager.autoLoginUser = "eric";
    sudo.enable = true;
    sudo.extraRules = [
      {
        users = [ "eric" ];
        commands = [
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
  };

  # Syncthing — bidirectional home folder sync with hwc-server
  hwc.data.syncthing = {
    enable = true;
    devices."hwc-server" = {
      id = "5UCUDT4-CUUGX7U-F2XVLET-SE3QGCA-JRYGXK3-45MQOBP-SYMQZM7-O653IAA";
      addresses = [ "tcp://100.114.232.124:22000" ];  # Server Tailscale IP
    };
    folders = {
      "000_inbox"    = { path = "/home/eric/000_inbox";    devices = [ "hwc-server" ]; };
      "100_hwc"      = { path = "/home/eric/100_hwc";      devices = [ "hwc-server" ]; };
      "200_personal" = { path = "/home/eric/200_personal"; devices = [ "hwc-server" ]; };
      "300_tech"     = { path = "/home/eric/300_tech";     devices = [ "hwc-server" ]; };
      "700_datax"    = { path = "/home/eric/700_datax";    devices = [ "hwc-server" ]; };
      # 600_apps: removed from Syncthing 2026-06-16 (see server config). Each app
      # is its own git repo now; Syncthing over live .git was clobbering
      # lead_scout/sr_analyzer. git is the only sync. Same fix as brain below.
      # brain: NOT a Syncthing folder on the laptop. Tier-2 = git is the only
      # laptop<->server vault sync (clone of the bare hub; Obsidian-git or CLI
      # pull/push). Removed from Syncthing 2026-06-15 to eliminate the
      # git-on-a-multi-writer-tree clobber at the root.
      "screenshots"  = { path = "/home/eric/500_media/510_pictures/screenshots"; devices = [ "hwc-server" ]; };
    };
  };

  # Brain vault git sync — Tier-2 transport on the laptop. Every 15 min: commit
  # local vault edits (CLI / Claude Code / Obsidian), pull the hub, push back —
  # so notes made on the laptop propagate to the server + phone automatically,
  # no manual push and no dependence on Obsidian being open.
  # PREREQ: the laptop vault's `origin` must be the bare hub
  # (eric@hwc-server:/var/lib/vault-backups/git/brain.git) reachable over SSH
  # non-interactively (passphraseless key / Tailscale SSH) for the eric-run
  # service to push. Verify after rebuild: `systemctl start brain-vault-sync`.
  hwc.automation.vaultSync.enable = true;
  # Event-driven: push within ~3s of any vault CRUD (Claude Code / CLI /
  # Obsidian), instead of waiting up to the 15-min timer. The timer stays on for
  # the periodic pull + as a backstop.
  hwc.automation.vaultSync.watch.enable = true;

  # Seagate Backup Plus Drive — NTFS via ntfs3 kernel driver
  # UUID-based so it works regardless of device enumeration order (/dev/sdb vs /dev/sdc etc.)
  # noauto: not mounted at boot (USB may not be present). Mount manually: sudo mount /mnt/seagate
  # seagate-fixperms.service: chowns root-owned dirs after each mount so Yazi can delete
  fileSystems."/mnt/seagate" = {
    device = "/dev/disk/by-uuid/A802BE5102BE23EA";
    fsType = "ntfs3";
    options = [
      "uid=1000" "gid=100" "dmask=0000" "fmask=0000"
      "force" "iocharset=utf8"
      "noauto" "nofail"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/seagate 0755 root root -"

    # Claude Desktop Cowork path parity: on macOS/Windows the workspace lives at
    # the VM path /sessions/<id>/mnt/...; the Linux port has no VM and expects a
    # /sessions symlink into its host session store (its docs do this once via
    # sudo). Declaring it here means /sessions/... paths the model constructs
    # resolve directly, matching the Mac/Windows layout. Companion to
    # hwc.system.core.envfs.enable above. See domains/home/apps/claude-desktop.
    "L+ /sessions - - - - /home/eric/.config/Claude/local-agent-mode-sessions/sessions"
  ];

  # USB auto-mount for external drives + NTFS fixperms for Seagate
  hwc.system.usb.autoMount.enable = true;
  hwc.system.usb.ntfsFixperms = [{
    mountPoint = "/mnt/seagate";
    afterUnit = "mnt-seagate.mount";
  }];

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
  virtualisation.docker.enable = lib.mkForce false;

  #============================================================================
  # === [profiles/home-session.nix] Orchestration =============================
  #============================================================================
  # System-lane dependencies for home apps (co-located sys.nix files)
  # These are enabled separately because system evaluates before Home Manager
  hwc.system.apps.hyprland.enable = true;   # Startup script, helper scripts
  hwc.system.apps.waybar.enable = true;     # System dependency validation
  hwc.system.apps.chromium.enable = true;   # System integration (dconf, dbus)
  hwc.system.apps.gpu-screen-recorder.enable = true;  # setcap gsr-kms-server (Wayland capture)

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

  # AI model storage. ai.root is null on non-server hosts (paths.nix), but the
  # llama.cpp module asserts an absolute modelsDir derived from ai.models. Point
  # it at /opt/ai so models land in /opt/ai/models/llama-cpp (matches the server).
  hwc.paths.ai.root = "/opt/ai";

  # Machine-specific Home Manager overrides live in ./home.nix (HM lane),
  # wired by the flake glue for both nixos-rebuild and standalone hms.

  #============================================================================
  # AI DOMAIN CONFIGURATION (Laptop)
  #============================================================================
  # Profile auto-detection: laptop (GPU: nvidia, RAM: 32GB < 16GB threshold)
  # Result: Conservative limits (2 cores, 4GB, 70°C warning, 80°C critical)
  hwc.ai = {
    # Profile selection (auto-detects laptop based on RAM/GPU)
    profiles.selected = "auto";
    # ai.tools removed 2026-07-05 (audit 2.2): was enabled here but zero
    # shell-history usage ever — dead by the "deployed + used" principle.
  };

  # Local llama.cpp inference (reuses the server module in-place). Laptop runs
  # ONLY the GPU chat model + embeddings — NOT the 24B CPU service (won't fit
  # the 8GB VRAM, and CPU inference is the fan-noise condition we're avoiding).
  #   GPU:   LFM2-2.6B Q4 (~1.5 GB)  127.0.0.1:11500  (alias lfm2-2.6b)
  #   Embed: nomic-embed-text-v1.5   127.0.0.1:11502
  hwc.server.ai.llamaCpp = {
    enable = true;
    # pkgs-laptop has no global cudaSupport (unlike the server's stable-cuda
    # set), so force the CUDA backend per-package — otherwise -ngl is silently
    # ignored and inference falls back to the CPU. cudaCapabilities stays null:
    # the nixpkgs default arch list (75;80;86;89;...) already covers the
    # RTX 2000 Ada (sm_89), so no arch rebuild is needed beyond the backend.
    cudaSupport = true;
    gpu = {
      enable = true;
      threads = 8;                          # cap under the 22 logical cores; GPU does the work
      extraArgs = [ "--alias" "lfm2-2.6b" ]; # stable model name for the wrapper/clients
    };
    embed.enable = true;                     # RAG embeddings, same model/flags as the server
    # cpu.enable left false → 24B CPU service intentionally skipped.
  };

  #============================================================================
  # === [domains/data/databases] Orchestration ================================
  #============================================================================
  # Local development PostgreSQL — vanilla, listens on localhost only.
  # No Podman networking, no vchord/pgvector (server-only for Immich).
  # Data dir: /var/lib/hwc/postgresql (fresh cluster on first boot).
  # Laptop runs v17 (server is pinned to v15 by its existing cluster).
  hwc.data.databases.postgresql = {
    enable = true;
    version = "17";
    package = pkgs.postgresql_17;
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

      # Boost control (disable turbo on AC too — Meteor Lake turbo bursts spike
      # temps past the fan trip points and slam the fan to max; capping heat at
      # the source keeps the machine quiet. Reversible: set back to 1 if you
      # need peak burst perf on AC.)
      CPU_BOOST_ON_AC = 0;
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

  # Device rules: kyber scheduler on NVMe
  services.udev.extraRules = lib.mkAfter ''
    ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
  '';

  # Intel NPU support (permissions, firmware, Level Zero loader)
  hardware.cpu.intel.npu.enable = true;

  # Add Level Zero and OpenCL runtime for NPU backend, plus Intel iGPU
  # VA-API stack (machine-local: this laptop has both Intel iGPU and NVIDIA
  # dGPU, and the Wayland compositor + chromium render on the iGPU).
  hardware.graphics.extraPackages = with pkgs; [
    level-zero
    intel-compute-runtime
    intel-media-driver   # iHD VA-API driver for Meteor Lake / Arc iGPU
    libvdpau-va-gl       # VDPAU<->VAAPI bridge
  ];

  # Performance mode wrappers (perf-mode/balanced-mode) — system hardware domain
  hwc.system.hardware.powerScripts.enable = true;

  programs.dconf.enable = true;
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  # nix-ld: enabled in profiles/core.nix (all machines)
}
