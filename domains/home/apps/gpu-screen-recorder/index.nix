# domains/home/apps/gpu-screen-recorder/index.nix
# Screen recording for calls (Zoom / Google Meet) — GPU-encoded, low overhead.
#
# This module ships ONLY the gsr-toggle start/stop script. The
# gpu-screen-recorder binary itself comes from the system lane
# (hwc.system.apps.gpu-screen-recorder → sys.nix): the nixpkgs module
# applies a wrapperDir override so the binary execs the setcap'd
# gsr-kms-server from /run/wrappers/bin. Installing the plain package
# here would shadow that copy in PATH and break promptless capture —
# see sys.nix for the full explanation.
#
# Keybind: hyprland/parts/behavior.nix adds SHIFT+PRINT → gsr-toggle
# when this module is enabled (same pattern as the dt toggle bind).
# Waybar: waybar/parts/behavior.nix adds a custom/recording widget driven
# by gsr-status (click = gsr-toggle, red while recording). gsr-toggle
# signals waybar with RTMIN+9 for instant refresh; the widget also polls
# as a fallback in case the recorder dies without a toggle.

{ lib, config, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.gpu-screen-recorder;

  # HELPERS — recordings dir from system paths (Law 1: safe when osConfig = {});
  # the fallback literal is the documented Law 3 escape hatch for standalone HM.
  recordingsDir =
    let p = lib.attrByPath [ "hwc" "paths" "recordings" ] null osConfig;
    in if p != null then p
       else "${config.home.homeDirectory}/500_media/530_videos/recordings";

  # The recording runs as its OWN transient user unit (gsr-record.service via
  # systemd-run), never as a child of the invoker. Two hard-won reasons:
  # - A click-started recording would otherwise live in waybar.service's
  #   cgroup and be SIGKILLed (file unfinalized) whenever waybar restarts.
  # - `systemctl is-active` gives exact recording state; the previous
  #   `pgrep -f 'gpu-screen-recorder -w'` false-matched ANY process whose
  #   cmdline contained that string (e.g. a shell running a grep for it).
  #
  # The waybar refresh signal MUST target only the waybar binary (comm
  # `.waybar-wrapped` under nix, `waybar` otherwise). A bare `pkill ... waybar`
  # also matches `waybar-launch` — the bash wrapper that is waybar.service's
  # MainPID — and bash dies on unhandled RT signals, so systemd fails the
  # service and SIGKILLs its whole cgroup (journal: status=43/RTMIN+9).
  signalWaybar = ''${pkgs.procps}/bin/pkill -RTMIN+9 -x '\.waybar-wrapped|waybar' || true'';

  gsrToggle = pkgs.writeShellScriptBin "gsr-toggle" ''
    set -euo pipefail

    DIR="''${HWC_RECORDINGS_DIR:-${recordingsDir}}"

    # Already recording → stop (SIGINT finalizes the file), wait, notify
    if systemctl --user is-active --quiet gsr-record.service; then
      systemctl --user kill --signal=SIGINT gsr-record.service
      for _ in $(seq 1 50); do
        STATE=$(systemctl --user is-active gsr-record.service 2>/dev/null || true)
        [[ "$STATE" == "active" || "$STATE" == "deactivating" ]] || break
        sleep 0.2
      done
      ${pkgs.libnotify}/bin/notify-send -t 4000 "⏹ Recording saved" "$DIR"
      ${signalWaybar}
      exit 0
    fi

    # Binary comes from the system lane; fail loud if that half is missing
    BIN=$(command -v gpu-screen-recorder) || {
      ${pkgs.libnotify}/bin/notify-send -u critical "gpu-screen-recorder not found" \
        "Enable hwc.system.apps.gpu-screen-recorder and nixos-rebuild."
      exit 1
    }

    MONITOR=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
    mkdir -p "$DIR"
    OUT="$DIR/rec_$(date +%Y-%m-%d_%H-%M-%S).mp4"

    systemd-run --user --quiet --collect --unit=gsr-record \
      --setenv=WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" \
      --setenv=HYPRLAND_INSTANCE_SIGNATURE="''${HYPRLAND_INSTANCE_SIGNATURE:-}" \
      "$BIN" -w "$MONITOR" -f ${toString cfg.fps} \
      -a ${lib.escapeShellArg cfg.audio} -o "$OUT"
    ${pkgs.libnotify}/bin/notify-send -t 4000 "⏺ Recording $MONITOR" "$OUT"
    ${signalWaybar}
  '';

  # Waybar JSON status (class drives the red-while-recording CSS)
  gsrStatus = pkgs.writeShellScriptBin "gsr-status" ''
    set -euo pipefail
    if systemctl --user is-active --quiet gsr-record.service; then
      printf '{"text":"Rec","class":"recording","tooltip":"Screen recording: RECORDING\\nSHIFT+PRINT or click to stop"}\n'
    else
      printf '{"text":"Rec","class":"off","tooltip":"Screen recording: off\\nSHIFT+PRINT or click to start"}\n'
    fi
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.gpu-screen-recorder = {
    enable = lib.mkEnableOption "gsr-toggle screen-recording script (call recording)";

    fps = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Capture framerate (30 is plenty for calls; raise for motion-heavy content)";
    };

    audio = lib.mkOption {
      type = lib.types.str;
      default = "default_output|default_input";
      description = "gpu-screen-recorder -a value; '|' merges sources into one track (call audio + mic)";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ gsrToggle gsrStatus ];
  };
}
