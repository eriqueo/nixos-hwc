{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.gaming.retroarch;
  paths = config.hwc.paths;

  # Keep the executable payload beside its wiring: index.nix owns options and
  # dependencies; stream-session.py preserves the exercised pilot supervisor.
  streamState = "${cfg.dataDir}/config/katamari-stream-pilot";
  streamRuntime = "/run/hwc/sunshine";
  tvState = "${cfg.dataDir}/config/tv";
  tvRuntime = "/run/hwc/tv";
  streamCatalog = (pkgs.formats.json {}).generate "sunshine-game-catalog.json" {
    schemaVersion = 1;
    roms = cfg.romsDir;
    games = cfg.sunshine.games;
  };
  streamSession = pkgs.replaceVarsWith {
    src = ./stream-session.py;
    isExecutable = true;
    replacements = {
      python = lib.getExe pkgs.python3;
      state = streamState;
      runtime = streamRuntime;
      inherit tvRuntime;
      pcsx = "${pkgs.pcsx2}/bin/pcsx2-qt";
      dolphin = "${pkgs.dolphin-emu}/bin/dolphin-emu";
      catalog = streamCatalog;
      xvfb = "${pkgs.xorg-server}/bin/Xvfb";
      pulse = "${pkgs.pulseaudio}/bin/pulseaudio";
      openbox = "${pkgs.openbox}/bin/openbox";
      sunshine = lib.getExe config.services.sunshine.package;
      libx11 = pkgs.libX11;
      libxtst = pkgs.libXtst;
    };
  };
  streamApps = (pkgs.formats.json {}).generate "sunshine-headless-apps.json" {
    env = {};
    apps = [
      { name = "Desktop"; }
      {
        name = "RetroArch";
        cmd = "${retroarchWithCores}/bin/retroarch --menu --fullscreen";
        auto-detach = false;
        wait-all = true;
      }
    ] ++ map (game: {
        name = game.title;
        cmd = "${streamSession} game ${lib.escapeShellArg game.id}";
        working-dir = streamState;
        auto-detach = false;
        wait-all = true;
        exit-timeout = 10;
        output = "${streamState}/game-launch.log";
      }) cfg.sunshine.games;
  };
  streamConf = (pkgs.formats.keyValue {}).generate "sunshine-headless.conf" {
    sunshine_name = config.networking.hostName;
    capture = "x11";
    encoder = "nvenc";
    audio_sink = "katamari_stream";
    virtual_sink = "katamari_stream";
    channels = 1;
    gamepad = "x360";
    upnp = "disabled";
    origin_web_ui_allowed = "wan";
    bind_address = cfg.sunshine.bindAddress;
    port = cfg.sunshine.port;
    address_family = "ipv4";
    file_apps = streamApps;
    file_state = "${streamState}/state.json";
    credentials_file = "${streamState}/credentials.json";
    pkey = "${streamState}/server-key.pem";
    cert = "${streamState}/server-cert.pem";
    log_path = "/dev/null"; # Console logs go to the host's bounded journal.
    min_log_level = 2;
  };

  # REPLACEABLE launcher metadata is generated from the one game catalog.
  # Native app sign-in/preferences are CRITICAL under cfg.dataDir (existing backup owner).
  tvMetadata = pkgs.writeTextDir "metadata.pegasus.txt" (''
    collection: Movies
    shortname: movies
    file: ${lib.getExe pkgs.jellyfin-desktop}

    game: Jellyfin
    file: ${lib.getExe pkgs.jellyfin-desktop}
    launch: ${lib.getExe pkgs.jellyfin-desktop} --tv --fullscreen --config-dir ${lib.escapeShellArg "${tvState}/jellyfin"}

    collection: Games
    shortname: games
    ${lib.concatMapStringsSep "\n" (game: "file: ${cfg.romsDir}/${game.rom}") cfg.sunshine.games}

  '' + lib.concatMapStringsSep "\n" (game: ''
    game: ${game.title}
    file: ${cfg.romsDir}/${game.rom}
    launch: ${streamSession} local-game ${lib.escapeShellArg game.id}
  '') cfg.sunshine.games);
  tvGameDirs = pkgs.writeText "tv-game-dirs.txt" "${tvMetadata}\n";
  tvSession = pkgs.writeShellScript "hwc-tv-session" ''
    set -eu
    export XDG_CONFIG_HOME=${lib.escapeShellArg "${tvState}/config"}
    export QT_QPA_PLATFORM=xcb
    export QT_QPA_PLATFORMTHEME=generic
    export QT_STYLE_OVERRIDE=Fusion
    ${lib.optionalString (cfg.tv.audioSink != "") "export PULSE_SINK=${lib.escapeShellArg cfg.tv.audioSink}"}
    ${pkgs.xset}/bin/xset s off
    ${pkgs.xset}/bin/xset -dpms
    ${pkgs.util-linux}/bin/setsid ${pkgs.openbox}/bin/openbox --sm-disable &
    wm=$!
    launcher=""
    cleanup() {
      trap - EXIT TERM INT
      [ -z "$launcher" ] || kill -- -"$launcher" 2>/dev/null || true
      kill -- -"$wm" 2>/dev/null || true
      # Separate process groups exclude the existing Pi session. Two-second drain.
      ${pkgs.coreutils}/bin/sleep 2
      [ -z "$launcher" ] || kill -KILL -- -"$launcher" 2>/dev/null || true
      kill -KILL -- -"$wm" 2>/dev/null || true
    }
    trap cleanup EXIT TERM INT
    ${pkgs.util-linux}/bin/setsid ${pkgs.pegasus-frontend}/bin/pegasus-fe --disable-menu-reboot --disable-menu-shutdown --disable-menu-suspend &
    launcher=$!
    wait "$launcher"
  '';

  # RetroArch with selected cores
  retroarchWithCores = pkgs.retroarch.withCores (cores:
    lib.filter (x: x != null) [
      (if cfg.cores.dosbox-pure then cores.dosbox-pure else null)
      (if cfg.cores.snes9x then cores.snes9x else null)
      (if cfg.cores.mgba then cores.mgba else null)
      (if cfg.cores.mupen64plus then cores.mupen64plus else null)
      (if cfg.cores.genesis-plus-gx then cores.genesis-plus-gx else null)
      (if cfg.cores.nestopia then cores.nestopia else null)
      (if cfg.cores.beetle-psx-hw then cores.beetle-psx-hw else null)
      (if cfg.cores.flycast then cores.flycast else null)
    ]
  );
in
{
  # OPTIONS
  options.hwc.gaming.retroarch = {
    enable = lib.mkEnableOption "RetroArch emulator with game streaming via Sunshine";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc/retroarch";
      description = "Directory for RetroArch configuration and data";
    };

    romsDir = lib.mkOption {
      type = lib.types.path;
      default = toString paths.media.retroarch.roms;
      description = "Directory containing ROM files";
    };

    systemDir = lib.mkOption {
      type = lib.types.path;
      default = toString paths.media.retroarch.system;
      description = "Directory containing BIOS and system files";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU hardware acceleration for emulation and streaming";
    };

    tv = {
      enable = lib.mkEnableOption "Boot into the local Movies and Games TV session";
      audioSink = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Native PulseAudio/PipeWire sink for the physical TV apps; empty uses the user's default";
      };
    };

    cores = {
      # Core emulator selection - enable what you need
      dosbox-pure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "DOSBox Pure core for DOS/Windows games";
      };

      snes9x = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Snes9x core for SNES games";
      };

      mgba = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "mGBA core for GBA games";
      };

      mupen64plus = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Mupen64Plus core for N64 games";
      };

      pcsx2 = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "PCSX2 core for PS2 games (requires beefy hardware)";
      };

      dolphin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Dolphin core for GameCube/Wii games";
      };

      genesis-plus-gx = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Genesis Plus GX core for Sega Genesis/CD/Master System";
      };

      nestopia = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nestopia core for NES games";
      };

      beetle-psx-hw = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Beetle PSX HW core for PlayStation games (hardware renderer)";
      };

      flycast = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Flycast core for Dreamcast games";
      };
    };

    sunshine = {
      enable = lib.mkEnableOption "Sunshine game streaming server (Moonlight compatible)";

      headless = lib.mkEnableOption "Managed headless streaming using existing private pairing and game state";

      games = lib.mkOption {
        default = [];
        description = "Direct Sunshine game launchers; ROM paths are relative to romsDir";
        type = lib.types.listOf (lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.strMatching "[a-z0-9]+(-[a-z0-9]+)*"; };
            title = lib.mkOption { type = lib.types.str; };
            system = lib.mkOption { type = lib.types.enum [ "ps2" "gamecube" ]; };
            rom = lib.mkOption { type = lib.types.str; };
          };
        });
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Tailscale address for the headless Sunshine listener";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 47989;
        description = "Web UI port for Sunshine";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall ports for Sunshine streaming";
      };

      capSysAdmin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CAP_SYS_ADMIN for mouse/keyboard emulation";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall ports for RetroArch netplay";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install RetroArch with cores system-wide
    environment.systemPackages = [
      retroarchWithCores
      pkgs.retroarch-assets
      pkgs.libretro-shaders-slang
    ] ++ lib.optionals cfg.tv.enable [ pkgs.pegasus-frontend pkgs.jellyfin-desktop pkgs.alsa-utils ]
      ++ lib.optionals cfg.sunshine.enable [
      pkgs.sunshine
      pkgs.moonlight-qt  # Client for testing
    ];

    # Sunshine game streaming service
    services.sunshine = lib.mkIf cfg.sunshine.enable {
      enable = true;
      autoStart = !cfg.sunshine.headless;
      capSysAdmin = cfg.sunshine.capSysAdmin;
      openFirewall = cfg.sunshine.openFirewall;
    };

    # CRITICAL: the existing private pairing and emulator state stays in place.
    # No prepare/reset command runs here. Runtime files are REPLACEABLE and
    # systemd removes them on stop; the host journal bounds console logs.
    systemd.services.sunshine-headless = lib.mkIf (cfg.sunshine.enable && cfg.sunshine.headless) {
      description = "Headless Sunshine streaming desktop";
      wantedBy = [ "multi-user.target" ];
      wants = [ "user@1000.service" "tailscaled.service" ];
      after = [ "user@1000.service" "tailscaled.service" ];
      path = [ pkgs.coreutils pkgs.xauth pkgs.xrandr ];
      environment = {
        HOME = config.users.users.eric.home;
        XDG_RUNTIME_DIR = "/run/user/1000";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      };
      serviceConfig = {
        Type = "notify";
        TimeoutStartSec = 120;
        User = lib.mkForce "eric";
        Group = "users";
        SupplementaryGroups = [ "uinput" "input" "video" "render" ];
        RuntimeDirectory = "hwc/sunshine";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${streamSession} run ${streamConf}";
        KillMode = "control-group";
        TimeoutStopSec = 15;
        Restart = "no"; # Fail visibly; do not loop on a broken display or encoder.
      };
    };

    # Physical TV and virtual Pi streaming use separate display/audio sessions.
    services.xserver = lib.mkIf cfg.tv.enable {
      enable = true;
      displayManager.lightdm.enable = true;
      displayManager.session = [{
        name = "hwc-tv";
        manage = "desktop";
        start = ''
          ${tvSession} &
          waitPID=$!
        '';
      }];
    };
    services.displayManager = lib.mkIf cfg.tv.enable {
      defaultSession = "hwc-tv";
      autoLogin = { enable = true; user = "eric"; };
    };

    # RetroArch data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 eric users -"
      "d ${cfg.dataDir}/config 0755 eric users -"
      "d ${cfg.dataDir}/saves 0755 eric users -"
      "d ${cfg.dataDir}/states 0755 eric users -"
      "d ${cfg.dataDir}/screenshots 0755 eric users -"
      "d ${cfg.dataDir}/system 0755 eric users -"
      "d ${cfg.dataDir}/playlists 0755 eric users -"
      "d ${cfg.dataDir}/thumbnails 0755 eric users -"
    ] ++ lib.optionals cfg.tv.enable [
      "d ${tvState} 0700 eric users -"
      "d ${tvState}/config 0700 eric users -"
      "d ${tvState}/config/pegasus-frontend 0700 eric users -"
      "d ${tvState}/jellyfin 0700 eric users -"
      "d ${tvRuntime} 0700 eric users -"
      "L+ ${tvState}/config/pegasus-frontend/game_dirs.txt - - - - ${tvGameDirs}"
    ];

    # Firewall configuration for RetroArch netplay
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 55435 ];  # RetroArch netplay
      allowedUDPPorts = [ 55435 ];
    };

    # GPU access for hardware-accelerated emulation
    # This allows RetroArch and Sunshine to use GPU rendering
    hardware.graphics = lib.mkIf cfg.gpu.enable {
      enable = true;
      enable32Bit = true;  # For 32-bit cores/games
    };

    # Ensure user has video group access for GPU
    users.users.eric.extraGroups = lib.mkIf cfg.gpu.enable [
      "video"
      "render"
      "input"  # For controller access
    ];

    # udev rules for game controllers
    services.udev.extraRules = ''
      # Xbox controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="045e", MODE="0666"
      # PlayStation controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="054c", MODE="0666"
      # Nintendo controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="057e", MODE="0666"
      # Generic HID gamepads
      KERNEL=="hidraw*", ATTRS{idVendor}=="045e", MODE="0666"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0666"
      KERNEL=="hidraw*", ATTRS{idVendor}=="057e", MODE="0666"
    '';

    # Sunshine user service enhancements for GPU access
    # NOTE: Sunshine runs as a user service (systemd.user.services), not a system service
    systemd.user.services.sunshine = lib.mkIf (cfg.sunshine.enable && cfg.gpu.enable) {
      environment = {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility,graphics";
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.tv.enable || (cfg.gpu.enable && cfg.sunshine.headless
          && config.hwc.system.hardware.audio.enable
          && !config.hwc.system.core.session.loginManager.enable);
        message = "Local TV requires GPU/audio, the retained headless streaming session, and no competing login manager";
      }
      {
        assertion = let games = cfg.sunshine.games; in
          lib.length (lib.unique (map (game: game.id) games)) == lib.length games
          && lib.length (lib.unique (map (game: game.title) games)) == lib.length games
          && lib.all (game: game.title != "" && !(lib.hasInfix "\n" game.title)
            && !(lib.hasInfix "\n" game.rom) && !(lib.hasPrefix "/" game.rom)
            && !(lib.elem ".." (lib.splitString "/" game.rom))) games;
        message = "Sunshine games require unique IDs/titles and ROM paths inside romsDir";
      }
      {
        assertion = !cfg.sunshine.headless || cfg.sunshine.bindAddress != "";
        message = "Headless Sunshine requires an explicit Tailscale bind address";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
        message = "hwc.gaming.retroarch.gpu requires hwc.system.hardware.gpu.enable = true";
      }
      {
        assertion = !(cfg.sunshine.enable && !cfg.gpu.enable);
        message = "Sunshine streaming requires GPU acceleration (hwc.gaming.retroarch.gpu.enable = true)";
      }
    ];
  };
}
