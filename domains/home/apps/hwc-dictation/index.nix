# Thin deployment adapter for the owned Voxtype fork. The app owns behavior,
# protocol, recovery limits and tests; this module supplies desktop settings.
{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:
let
  cfg = config.hwc.home.apps.hwc-dictation;
  app = inputs.hwc-dictation.packages.${pkgs.stdenv.hostPlatform.system};
  toml = pkgs.formats.toml { };
  colors = config.hwc.home.theme.colors;
  paletteFile = toml.generate "hwc-dictation-colors.toml" {
    background = "#${colors.bg0}";
    foreground = "#${colors.fg0}";
    accent = "#${colors.warning}";
    color1 = "#${colors.error}";
    color2 = "#${colors.success}";
    color3 = "#${colors.warning}";
  };
  settings = {
    dictation = {
      enabled = true;
      engine_policy = cfg.enginePolicy;
      # AUTO-MANAGED: app bounds 32 takes / 256 MiB, acknowledged success 24h.
      # HWC-EXCEPTION(Law 8): recovery has no independent file-deletion timer.
      # Justification: only the app knows which takes are protected; admission
      # refuses capacity overflow and prunes eligible takes on startup/reserve.
      # Plan: permanent by design; archive retention belongs to a later feature.
      # Revocable: yes
      recovery_dir = "${config.xdg.stateHome}/hwc-dictation/recovery";
    };
    hotkey.enabled = false;
    audio = {
      device = "default";
      max_duration_secs = 60;
      duck_media = false;
    };
    whisper = {
      mode = "local";
      model = cfg.model;
      language = "en";
      threads = 4;
      # Reduced context mistranscribed the one-second speech fixture.
      context_window_optimization = false;
      gpu_isolation = true;
      on_demand_loading = false;
      remote_endpoint = cfg.remoteEndpoint;
      remote_model = "whisper-1";
      remote_timeout_secs = 30;
      streaming = false;
      eager_processing = false;
    };
    output = {
      mode = "paste";
      target_guard = true;
      auto_submit = false;
      restore_clipboard = false;
      app_paste_keys = {
        t3code = "ctrl+v";
        chromium-browser = "ctrl+v";
        kitty = "ctrl+shift+v";
      };
      notification = {
        on_transcription = false;
      };
    };
    osd = {
      enabled = true;
      frontend = "gtk4";
      theme_file = toString paletteFile;
      # Permanent desktop layout: fixed corner margins stay on the selected
      # output. Centered fractional placement uses the first monitor's height,
      # which placed the panel below the shorter external display.
      position = "top-right";
      margin_px = 64;
      width_px = 480;
      height_px = 80;
    };
  };
  configFile = toml.generate "hwc-dictation.toml" settings;
  launcher = pkgs.writeShellScriptBin "hwc-dictation" ''
    exec ${cfg.package}/bin/voxtype --config ${configFile} "$@"
  '';
in
{
  options.hwc.home.apps.hwc-dictation = {
    enable = lib.mkEnableOption "HWC desktop dictation";
    package = lib.mkOption {
      type = lib.types.package;
      default = app.default;
      description = "Tested CPU or GPU dictation package.";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "${config.hwc.home.apps.whisper-cpp.modelsDir}/ggml-medium.en.bin";
      description = "Existing local GGML model.";
    };
    enginePolicy = lib.mkOption {
      type = lib.types.enum [
        "local"
        "remote"
        "prefer_remote"
      ];
      default = "prefer_remote";
      description = "Default engine policy for a new take.";
    };
    remoteEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://whisper.hwc.iheartwoodcraft.com";
      description = "Base URL of the transcription server.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      launcher
      cfg.package
      app.osd-gtk4
      pkgs.wtype
      pkgs.wl-clipboard
    ];
    systemd.user.services.hwc-dictation = {
      Unit = {
        Description = "HWC dictation";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "pipewire.service"
        ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStart = "${launcher}/bin/hwc-dictation daemon";
        Environment = [
          "GSK_RENDERER=gl"
          "PATH=${
            lib.makeBinPath [
              app.osd-gtk4
              pkgs.hyprland
              pkgs.wtype
              pkgs.wl-clipboard
              pkgs.libnotify
              pkgs.pulseaudio
            ]
          }"
        ];
        UMask = "0077";
        Restart = "no";
        # Allow the five-second engine drain and bounded OSD drain before group kill.
        TimeoutStopSec = 10;
        KillMode = "control-group";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    assertions = [
      {
        assertion = config.hwc.home.apps.whisper-cpp.enable;
        message = "HWC dictation requires the declared Whisper model provider.";
      }
    ];
  };
}
