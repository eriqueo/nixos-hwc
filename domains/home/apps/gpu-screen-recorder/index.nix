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

{ lib, config, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.gpu-screen-recorder;

  # HELPERS — recordings dir from system paths (Law 1: safe when osConfig = {});
  # the fallback literal is the documented Law 3 escape hatch for standalone HM.
  recordingsDir =
    let p = lib.attrByPath [ "hwc" "paths" "recordings" ] null osConfig;
    in if p != null then p
       else "${config.home.homeDirectory}/500_media/530_videos/recordings";

  gsrToggle = pkgs.writeShellScriptBin "gsr-toggle" ''
    set -euo pipefail

    DIR="''${HWC_RECORDINGS_DIR:-${recordingsDir}}"

    # Already recording → stop (SIGINT finalizes the file), wait, notify
    if ${pkgs.procps}/bin/pgrep -f 'gpu-screen-recorder -w' >/dev/null; then
      ${pkgs.procps}/bin/pkill -INT -f 'gpu-screen-recorder -w'
      for _ in $(seq 1 50); do
        ${pkgs.procps}/bin/pgrep -f 'gpu-screen-recorder -w' >/dev/null || break
        sleep 0.2
      done
      ${pkgs.libnotify}/bin/notify-send -t 4000 "⏹ Recording saved" "$DIR"
      exit 0
    fi

    # Binary comes from the system lane; fail loud if that half is missing
    if ! command -v gpu-screen-recorder >/dev/null; then
      ${pkgs.libnotify}/bin/notify-send -u critical "gpu-screen-recorder not found" \
        "Enable hwc.system.apps.gpu-screen-recorder and nixos-rebuild."
      exit 1
    fi

    MONITOR=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
    mkdir -p "$DIR"
    OUT="$DIR/rec_$(date +%Y-%m-%d_%H-%M-%S).mp4"

    gpu-screen-recorder -w "$MONITOR" -f ${toString cfg.fps} \
      -a ${lib.escapeShellArg cfg.audio} -o "$OUT" >/dev/null 2>&1 &
    disown
    ${pkgs.libnotify}/bin/notify-send -t 4000 "⏺ Recording $MONITOR" "$OUT"
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
    home.packages = [ gsrToggle ];
  };
}
