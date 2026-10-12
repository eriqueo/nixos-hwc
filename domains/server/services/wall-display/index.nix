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
# Screens (parts/screens.py), drawn with the TRMNL framework (served
# locally at /framework/): home (today's weather, top 3 tasks, events today
# and tomorrow), week (every Radicale event calendar + NOAA forecast/alerts),
# weather (NOAA now + 5 days), tasks (Things-style Deadlines / To-Dos /
# Finished today across every Radicale task list), briefing (allowlisted
# morning-briefing items, mail excluded). All but home carry a QR code to
# the matching phone page (`links` below). Protocol and rendering:
# parts/server.py.
#
# Devices are declared here: the protocol never reports a screen size, so
# each device's ID, resolution, scale, grey depth and playlist come from Nix. A
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

  # segno: QR codes as inline SVG (pure Python, no image stack).
  python = pkgs.python3.withPackages (p: [ p.icalendar p.segno ]);

  # Chromium lays out pages with these fonts only, so a render does not
  # depend on what the host happens to have installed.
  fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.noto-fonts ]; };
  # The same fonts with antialiasing off, for 2- and 4-grey renders: grey
  # glyph edges dither into noise at 1-2 bits. Chromium applies it to web
  # fonts too.
  crispFontsConf = pkgs.writeText "fonts-crisp.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <include>${fontsConf}</include>
      <match target="pattern"><edit name="antialias" mode="assign"><bool>false</bool></edit></match>
      <match target="font"><edit name="antialias" mode="assign"><bool>false</bool></edit></match>
    </fontconfig>
  '';

  # TRMNL framework v3.4.0 (CSS/JS MIT © TRMNL; fonts OFL 1.1 except
  # BlockKie CC BY 3.0) at the tag's commit, plus Weather Icons (Erik
  # Flowers, SVGs OFL 1.1). Fetched by hash, never committed (Law 13: the
  # CSS alone is 15 MB) and served by the server at /framework/, so a render
  # never touches the network. The CSS names its fonts as /fonts/…; they are
  # rewritten relative to the stylesheet. License texts ship in licenses/.
  frameworkRev = "9c41c06ef0797c701aae0e55d629345c6d1a2215"; # tag v3.4.0
  frameworkFiles = {
    "public/css/3.4.0/plugins.min.css" = "sha256-eaWNbALqkGcNjRvTStuw7lbw1+3Z5TWUbKmtae8qYds=";
    "public/js/3.4.0/plugins.min.js" = "sha256-orPBa//ZP5JeK+/u962TlICzQ53NJMJhv5BbTuIFe7Y=";
    "public/fonts/TRMNL12-Regular.woff2" = "sha256-/oxC+VsvsBAiKyiGFr2HyQ0ZyNEkRykcbhW7ae+ijEI=";
    "public/fonts/TRMNL12-Bold.woff2" = "sha256-4lOaeZRq0O2G+HyT8LjO/GuscD74n+4ChIcZd+JZKIU=";
    "public/fonts/TRMNL16-Regular.woff2" = "sha256-sgKDkdzizJ+6r4MM5IyzGFG/p0ivS9us8vwTK3YrFj0=";
    "public/fonts/TRMNL16-Bold.woff2" = "sha256-x4exPTW7ALAjnZqV4Kb+VJgErhqa9bdponyBFG6SBuU=";
    "public/fonts/TRMNL21-Regular.woff2" = "sha256-ip05pcwiwLxku+XGn9M6c73vr6sJdEYVTbNCom6wFoQ=";
    "public/fonts/TRMNL21-Bold.woff2" = "sha256-fTFEIobeeU5GJtXutDFSkh7OVqwUVcVI7Xv0VfTt4P4=";
    "public/fonts/Inter.ttf" = "sha256-C+I5nqkl8fg/+XR2R2HamGDsUHQu0ppdTB/9DFx6w6g=";
    "public/fonts/Inter-Italic.ttf" = "sha256-YTb3M3L+3De4D9Go7D4hc0Bz/xc3bzZycY8YZ3lnLno=";
    "public/fonts/NicoClean-Regular.ttf" = "sha256-PLB6dLZADU5QhfiF6fRaHELpkb5vuFnPl2kDLkmTNpo=";
    "public/fonts/NicoPups-Regular.ttf" = "sha256-BY1XzQ+1YRGnqII5v2EEEV6q1YVXcecZpzjEwW/X0os=";
    "public/fonts/BlockKie.ttf" = "sha256-ad47Rv6GJxmUxxaybVZJh0gzG4fLOwuZB3/9151LZcc=";
    "LICENSE" = "sha256-YlEg++m6Nbqx0Dds3FNSsPCMkdDGhxGljMYG5WPDF2s=";
    "THIRD_PARTY_NOTICES.md" = "sha256-vhc/NkdA0Jt6YrJjkgVIhJ8LiCiQpZAg/a7AzLK4mxQ=";
    "public/fonts/bundles/trmnl/OFL.txt" = "sha256-V/XxDHp5y3PcumM4Mj+3mkBl1FF7ITDED6J5U1zqps4=";
    "public/fonts/bundles/trmnl/README.md" = "sha256-2uSMVc6w9lyKtVJzZxEkNDhIwWRYgaMhKmTAhl0TVGY=";
    "public/fonts/bundles/classic/OFL.txt" = "sha256-TArd15tRG5Qz9dQfo8mGynZLF6yaQbFlqCRArs2YT9o=";
    "public/fonts/bundles/classic/CC-BY-3.0.txt" = "sha256-C9ZKlQj2oWdzRS/cFSYzlfu4lpIkBKAFR/RpprF2eQo=";
    "public/fonts/bundles/classic/README.md" = "sha256-ieqdKto75nqZZTjgaqqCjOUiyRXVCigbj7kOwHDwJHk=";
  };
  fw = path: pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/usetrmnl/trmnl-framework/${frameworkRev}/${path}";
    hash = frameworkFiles.${path};
  };
  weatherIcons = pkgs.fetchFromGitHub {
    owner = "erikflowers";
    repo = "weather-icons";
    rev = "bb80982bf1f43f2d57f9dd753e7413bf88beb9ed";
    hash = "sha256-OLeFqdCJeH44wHK4KpMDY3xse+0LxeHB6uj5p0Oa4fA=";
  };
  fontNames = lib.filter (p: lib.hasPrefix "public/fonts/" p && !lib.hasPrefix "public/fonts/bundles/" p)
    (lib.attrNames frameworkFiles);
  assets = pkgs.runCommand "wall-display-assets" { } ''
    d=$out/framework
    mkdir -p $d/fonts $d/icons $d/licenses/trmnl-fonts $d/licenses/classic-fonts
    substitute ${fw "public/css/3.4.0/plugins.min.css"} $d/plugins.css \
      --replace-fail 'url("/fonts/' 'url("fonts/'
    cp ${fw "public/js/3.4.0/plugins.min.js"} $d/plugins.js
    ${lib.concatMapStrings (p: "cp ${fw p} $d/fonts/${baseNameOf p}\n") fontNames}
    cp ${weatherIcons}/svg/*.svg $d/icons/
    cp ${fw "LICENSE"} $d/licenses/LICENSE
    cp ${fw "THIRD_PARTY_NOTICES.md"} $d/licenses/THIRD_PARTY_NOTICES.md
    cp ${fw "public/fonts/bundles/trmnl/OFL.txt"} $d/licenses/trmnl-fonts/OFL.txt
    cp ${fw "public/fonts/bundles/trmnl/README.md"} $d/licenses/trmnl-fonts/README.md
    cp ${fw "public/fonts/bundles/classic/OFL.txt"} $d/licenses/classic-fonts/OFL.txt
    cp ${fw "public/fonts/bundles/classic/CC-BY-3.0.txt"} $d/licenses/classic-fonts/CC-BY-3.0.txt
    cp ${fw "public/fonts/bundles/classic/README.md"} $d/licenses/classic-fonts/README.md
    cat > $d/licenses/WEATHER-ICONS.txt <<'EOF'
    icons/*.svg: Weather Icons by Erik Flowers (designs originally by Lukas
    Bischoff), https://github.com/erikflowers/weather-icons at commit
    bb80982bf1f43f2d57f9dd753e7413bf88beb9ed. The icons are licensed under
    the SIL Open Font License, Version 1.1; the full text is at the end of
    THIRD_PARTY_NOTICES.md and in trmnl-fonts/OFL.txt.
    EOF
  '';

  # Where each screen's QR code points (one producer; the server only reads
  # these). week → Calendar app, tasks → Tasks app, briefing → Workbench,
  # weather → the NWS point forecast for noaaPoint. home has none.
  vhostDomain = config.hwc.networking.shared.vhostDomain;
  latLon = lib.splitString "," cfg.noaaPoint;
  links = {
    week = "https://calendar.${vhostDomain}/";
    tasks = "https://todo.${vhostDomain}/";
    briefing = "https://workbench.${vhostDomain}/";
    weather = "https://forecast.weather.gov/MapClick.php?lat=${lib.elemAt latLon 0}&lon=${lib.elemAt latLon 1}";
  };

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
    assets = "${assets}";
    crispFontsConf = "${crispFontsConf}";
    inherit links;
    devices = cfg.devices;
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
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
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
          scale = lib.mkOption {
            type = lib.types.numbers.between 1 4;
            default = if config.width >= 1200 then 1.6 else 1.0;
            defaultText = lib.literalExpression "if width >= 1200 then 1.6 else 1.0";
            description = ''
              Device pixels per CSS pixel. Screens are laid out at
              width/scale x height/scale CSS pixels (the TRMNL framework's
              800-wide layouts) and captured at width x height; the Fire HD 8
              (1280x800) lays out at 800x500.
            '';
          };
          playlist = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.str;
            default = [ "home" "week" "weather" "tasks" "briefing" ];
            description = "Screens shown in turn, one per refresh. Names: home, week, weather, tasks, briefing (the server refuses others at boot).";
          };
          refreshRate = lib.mkOption {
            type = lib.types.ints.positive;
            default = 900;
            description = "Seconds the device waits before the next request (the TRMNL Android app cannot go below 900).";
          };
        };
      }));
      default = { };
      description = "Devices allowed to pair, keyed by a short name shown as the device's friendly_id.";
    };

    reverseProxy.enable = lib.mkEnableOption
      "Caddy vhost route (wall.hwc.iheartwoodcraft.com → this server)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.wall-display = {
      description = "Wall display (TRMNL BYOS server: home, week, weather, tasks, briefing)";
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
        MemoryMax = "1G";
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
        assertion = lib.allUnique (lib.filter (id: id != null) (lib.mapAttrsToList (_: d: d.id) cfg.devices));
        message = "hwc.server.services.wallDisplay.devices: two devices share one id.";
      }
    ];
  };
}
