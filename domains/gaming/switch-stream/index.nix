{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.gaming.switch-stream;
  home = config.hwc.paths.user.home;
  state = "${home}/.local/share/hwc-switch-stream";
  settings = (pkgs.formats.json {}).generate "switch-stream.json" {
    schemaVersion = 1;
    inherit state;
    host = cfg.bindAddress;
    pi = cfg.piAddress;
    gameRoot = cfg.gameRoot;
    games = cfg.games;
    backup = "${config.hwc.paths.backup}/gaming-state";
    edenConfig = "${home}/.config/eden/qt-config.ini";
    edenData = "${home}/.local/share/eden";
    monitor = "HWC-GAME";
    workspace = 99;
    binaries = {
      sunshine = lib.getExe pkgs.sunshine;
      eden = "${pkgs.eden}/bin/eden";
      hyprctl = "${pkgs.hyprland}/bin/hyprctl";
      pulse = "${pkgs.pulseaudio}/bin/pulseaudio";
      pactl = "${pkgs.pulseaudio}/bin/pactl";
      xdotool = "${pkgs.xdotool}/bin/xdotool";
    };
  };
  command = pkgs.writeShellScriptBin "hwc-switch-stream" ''
    exec ${lib.getExe pkgs.python3} ${./stream.py} ${settings} "$@"
  '';
  apps = (pkgs.formats.json {}).generate "switch-stream-apps.json" {
    env = {};
    apps = map (game: {
      name = game.title;
      cmd = "${command}/bin/hwc-switch-stream game ${lib.escapeShellArg game.id}";
      auto-detach = false;
      wait-all = true;
      exit-timeout = 15;
    }) cfg.games ++ [{
      name = "Switch library";
      cmd = "${command}/bin/hwc-switch-stream game library";
      auto-detach = false;
      wait-all = true;
      exit-timeout = 15;
    }];
  };
  sunshine = (pkgs.formats.keyValue {}).generate "switch-stream-sunshine.conf" {
    sunshine_name = config.networking.hostName;
    bind_address = cfg.bindAddress;
    capture = "wlr";
    output_name = "HWC-GAME";
    encoder = "vaapi"; # Exercised Intel encoder; Eden renders on the NVIDIA GPU.
    audio_sink = "hwc_switch_stream";
    virtual_sink = "hwc_switch_stream";
    mouse = false;
    keyboard = false;
    upnp = "disabled";
    origin_web_ui_allowed = "pc";
    file_apps = apps;
    credentials_file = "${state}/credentials.json";
    file_state = "${state}/state.json";
    pkey = "${state}/key.pem";
    cert = "${state}/cert.pem";
    log_path = "/dev/null";
  };
in {
  # OPTIONS
  options.hwc.gaming.switch-stream = {
    enable = lib.mkEnableOption "Switch streaming from an isolated Hyprland output to Batocera";
    bindAddress = lib.mkOption { type = lib.types.str; description = "Host Tailscale IPv4 address"; };
    piAddress = lib.mkOption { type = lib.types.str; description = "Batocera client SSH address (root)"; };
    gameRoot = lib.mkOption { type = lib.types.str; description = "Root containing user-owned Switch dumps"; };
    games = lib.mkOption {
      default = [];
      type = lib.types.listOf (lib.types.submodule { options = {
        id = lib.mkOption { type = lib.types.strMatching "[a-z0-9]+(-[a-z0-9]+)*"; };
        title = lib.mkOption { type = lib.types.str; };
        file = lib.mkOption { type = lib.types.str; description = "Dump path relative to gameRoot"; };
      }; });
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ command pkgs.sunshine ];
    hardware.uinput.enable = true;
    users.users.eric.extraGroups = [ "uinput" "input" "video" "render" ];

    # CRITICAL: pairing, saves and keys stay private and are never generated in
    # the store. `hwc-switch-stream backup` retains latest + previous snapshots
    # on the existing backup mount; original saves/keys have indefinite retention.
    # REPLACEABLE: user RuntimeDirectory is removed on stop; logs use the bounded journal.
    systemd.user.services.hwc-switch-stream = {
      description = "Switch streaming on an isolated Hyprland display and audio server";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      # Never interrupt a live trial or game when deploying this capability.
      unitConfig.ConditionPathExists = "!%t/hwc-switch-stream.defer";
      serviceConfig = {
        Type = "notify";
        ExecStart = "${command}/bin/hwc-switch-stream host-run ${sunshine}";
        RuntimeDirectory = "hwc-switch-stream";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        TimeoutStartSec = 90;
        TimeoutStopSec = 15;
        KillMode = "control-group";
        Restart = "no";
      };
    };

    # VALIDATION
    assertions = [{
      assertion = cfg.bindAddress != "" && cfg.piAddress != ""
        && lib.hasPrefix "/" cfg.gameRoot
        && lib.length (lib.unique (map (g: g.id) cfg.games)) == lib.length cfg.games
        && lib.length (lib.unique (map (g: g.title) cfg.games)) == lib.length cfg.games
        && lib.all (g: g.id != "library" && g.title != "" && !(lib.hasInfix "\n" g.title)
          && !(lib.hasPrefix "/" g.file) && !(lib.elem ".." (lib.splitString "/" g.file))) cfg.games;
      message = "Switch streaming requires explicit hosts, an absolute dump root and unique games with relative paths";
    } {
      assertion = !config.hwc.gaming.retroarch.sunshine.enable;
      message = "Switch streaming and RetroArch Sunshine cannot share the default listening ports on one host";
    }];
  };
}
