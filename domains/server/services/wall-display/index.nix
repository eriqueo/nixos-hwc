# domains/server/services/wall-display/index.nix
#
# Wall display — a TRMNL-compatible BYOS server for HWC's wall screens. It
# renders e-ink style screens (black on white, no colour, no motion) to
# greyscale PNGs and serves them to any device speaking the TRMNL BYOS
# protocol (the TRMNL Android app, TRMNL hardware, Kindle/Kobo clients).
# The same screens are served as HTML at /<screen> for browser kiosks, and
# /device/<name> is a web client (a browser shows the device's rotation as
# images and reloads itself; it survives reboots, which the TRMNL app does not).
#
# NAMESPACE: hwc.server.services.wallDisplay.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.server.services.wallDisplay.enable = true;   (machines/work/config.nix)
#
# Screens (parts/screens.py): week (every Radicale event calendar + NOAA
# forecast/alerts), tasks (every Radicale task list: due today, overdue,
# undated high priority), briefing (allowlisted morning-briefing items, mail
# excluded). Protocol and rendering: parts/server.py.
#
# Voice (voice.enable, parts/voice.py): the web client gets a mic button.
# POST /voice sends the recording to whisper, asks DX2 with a closed list of
# read tools (calendar, tasks, today queue, weather) and speaks the answer
# with a resident Piper. Task adds/completes only run after POST
# /voice/confirm (Yes button or a spoken "yes").
#
# Devices are declared here: the protocol never reports a screen size, so
# each device's ID, resolution, grey depth and playlist come from Nix. A
# device's api_key is minted at setup and kept in /var/lib/wall-display
# (REPLACEABLE: re-run setup in the client). Images there are pruned to the
# current and previous render per screen and size.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.wallDisplay;
  radicale = config.hwc.server.services.radicale;
  briefing = config.hwc.business.morningBriefing or { enable = false; };

  # Same tolerant lookup as the radicale module: the shared htpasswd secret.
  htpasswdPath = lib.attrByPath
    [ "age" "secrets" "radicale-htpasswd" "path" ]
    "/run/agenix/radicale-htpasswd"
    config;

  stateDir = "/var/lib/wall-display";
  briefingDir = if briefing.enable then briefing.outputDir else null;

  python = pkgs.python3.withPackages (p: [ p.icalendar ]);

  # Piper voice, pinned by hash at a fixed rhasspy/piper-voices revision.
  # piper 1.4 ignores -c and opens <model>.json, so both sit in one dir.
  piperVoiceName = "en_US-lessac-medium";
  piperVoiceBase = "https://huggingface.co/rhasspy/piper-voices/resolve/c10ece1aade47bb51c153c893d14e5bf8e5b7117/en/en_US/lessac/medium/${piperVoiceName}";
  piperVoice = pkgs.linkFarm "piper-voice-${piperVoiceName}" [
    {
      name = "${piperVoiceName}.onnx";
      path = pkgs.fetchurl {
        url = "${piperVoiceBase}.onnx";
        sha256 = "5efe09e69902187827af646e1a6e9d269dee769f9877d17b16b1b46eeaaf019f";
      };
    }
    {
      name = "${piperVoiceName}.onnx.json";
      path = pkgs.fetchurl {
        url = "${piperVoiceBase}.onnx.json";
        sha256 = "efe19c417bed055f2d69908248c6ba650fa135bc868b0e6abb3da181dab690a0";
      };
    }
  ];

  # Read only when voice is on: hosts without the DX2 module still evaluate.
  dx2 = config.hwc.server.ai.dx2;

  # Chromium lays out pages with these fonts only, so a render does not
  # depend on what the host happens to have installed.
  fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.noto-fonts ]; };

  # The one config the server reads (WALL_CONFIG); validated again at boot.
  serverConfig = pkgs.writeText "wall-display.json" (builtins.toJSON {
    port = cfg.port;
    inherit stateDir;
    timeZone = config.time.timeZone;
    radicale = {
      url = "http://127.0.0.1:${toString radicale.port}";
      user = cfg.calendarUser;
      htpasswdFile = htpasswdPath;
    };
    noaa = {
      point = cfg.noaaPoint;
      place = cfg.place;
      # api.weather.gov asks every client to identify itself.
      userAgent = "hwc-wall-display (https://iheartwoodcraft.com)";
    };
    briefingFile = if briefingDir != null then "${briefingDir}/briefing.json" else null;
    chromium = lib.getExe pkgs.chromium;
    magick = "${pkgs.imagemagick}/bin/magick";
    devices = cfg.devices;
    voice = if !cfg.voice.enable then null else {
      whisperUrl = cfg.voice.whisperUrl;
      dx2 = { inherit (dx2) baseUrl model apiKeyFile; };
      gatewayUrl = "http://127.0.0.1:${toString config.hwc.system.mcp.port}/mcp";
      piper = lib.getExe pkgs.piper-tts;
      model = "${piperVoice}/${piperVoiceName}.onnx";
      ffmpeg = lib.getExe pkgs.ffmpeg-headless;
    };
  });
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.services.wallDisplay = {
    enable = lib.mkEnableOption "wall display: TRMNL-compatible BYOS server + HTML screens";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8424;
      description = "Localhost port the server binds (fronted by Caddy).";
    };

    calendarUser = lib.mkOption {
      type = lib.types.str;
      default = radicale.mirrorUser;
      description = "Radicale principal whose calendars and task lists are shown (needs a line in the htpasswd secret).";
    };

    noaaPoint = lib.mkOption {
      type = lib.types.str;
      default = "45.6770,-111.0429";
      description = "\"lat,lon\" for the api.weather.gov forecast and alerts (default: Bozeman).";
    };

    place = lib.mkOption {
      type = lib.types.str;
      default = "Bozeman";
      description = "Place name shown before the current conditions.";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "44:00:49:05:31:49";
            description = ''
              The ID header a TRMNL BYOS client sends (the MAC or device ID
              entered in the client). null = web client only, at /device/<name>.
            '';
          };
          width = lib.mkOption { type = lib.types.ints.positive; description = "Screen width in pixels, as the device will show the image."; };
          height = lib.mkOption { type = lib.types.ints.positive; description = "Screen height in pixels."; };
          grays = lib.mkOption {
            type = lib.types.enum [ 2 4 16 ];
            default = 4;
            description = "Grey levels in the PNG: 2 (1-bit, TRMNL OG legacy), 4 (2-bit), 16 (4-bit, TRMNL X / tablets).";
          };
          playlist = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.str;
            default = [ "week" "tasks" "briefing" ];
            description = "Screens shown in turn, one per refresh. Names: week, tasks, briefing (the server refuses others at boot).";
          };
          refreshRate = lib.mkOption {
            type = lib.types.ints.positive;
            default = 900;
            description = "Seconds the device waits before the next request (the TRMNL Android app cannot go below 900).";
          };
        };
      });
      default = { };
      description = "Devices allowed to pair, keyed by a short name shown as the device's friendly_id.";
    };

    reverseProxy.enable = lib.mkEnableOption
      "Caddy vhost route (wall.hwc.iheartwoodcraft.com → this server)";

    voice = {
      enable = lib.mkEnableOption ''
        tap-to-talk in the web client: whisper → DX2 with a closed tool list
        → Piper. Writes (task add/complete) wait for a confirmation. Needs the
        hwc-sys MCP gateway and the DX2 module on this host'';

      whisperUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://whisper.${config.hwc.networking.shared.vhostDomain}";
        defaultText = lib.literalExpression ''"https://whisper.''${hwc.networking.shared.vhostDomain}"'';
        description = "Base URL of a whisper-server (POST <url>/v1/audio/transcriptions). Default: the `whisper` vhost.";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.wall-display = {
      description = "Wall display (TRMNL BYOS server: week, tasks, briefing)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "radicale.service" ];
      wants = [ "network-online.target" ];
      environment = {
        WALL_CONFIG = serverConfig;
        FONTCONFIG_FILE = fontsConf;
        HOME = stateDir; # Chromium's profile and crash dirs
      };
      serviceConfig = {
        ExecStart = "${python}/bin/python3 ${./parts}/server.py";
        User = lib.mkForce "eric";
        Group = "users";
        # Read the agenix-mounted htpasswd (0440 root:secrets).
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "wall-display";
        StateDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        # Only the briefing output is visible from /home.
        ProtectHome = "tmpfs";
        BindReadOnlyPaths = lib.optional (briefingDir != null) briefingDir;
        PrivateTmp = true;
        # Resident Piper holds ~200 MB beside the Chromium renders.
        MemoryMax = if cfg.voice.enable then "1536M" else "1G";
      };
    };

    hwc.networking.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        name = "wall";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = radicale.enable;
        message = "hwc.server.services.wallDisplay reads the local Radicale; enable hwc.server.services.radicale on this host.";
      }
      {
        assertion = config.time.timeZone != null;
        message = "hwc.server.services.wallDisplay needs time.timeZone set to place events on local days.";
      }
      {
        assertion = cfg.voice.enable -> (lib.hasAttrByPath [ "hwc" "server" "ai" "dx2" ] config
          && (config.hwc.system.mcp.enable or false));
        message = "hwc.server.services.wallDisplay.voice needs the DX2 module (domains/server/native/ai/dx2) and hwc.system.mcp.enable on this host.";
      }
      {
        assertion = lib.allUnique (lib.filter (id: id != null) (lib.mapAttrsToList (_: d: d.id) cfg.devices));
        message = "hwc.server.services.wallDisplay.devices: two devices share one id.";
      }
    ];
  };
}
