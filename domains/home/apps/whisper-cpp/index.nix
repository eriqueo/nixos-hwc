# domains/home/apps/whisper-cpp/index.nix
#
# whisper.cpp (CUDA build on machines with NVIDIA) plus declarative model
# management. Each requested model is fetched once via fetchurl (hash-pinned)
# and symlinked into modelsDir so `whisper-cli -m <modelsDir>/ggml-<name>.bin`
# resolves without imperative downloads.
#
# `dictate` adds a push-to-talk toggle (`whisper-dictate`) for the desktop:
# press once to record from the default mic, press again to stop; the text
# lands on the clipboard and is typed into the window that had focus when the
# recording started. Modelled on gpu-screen-recorder's gsr-toggle: the
# recorder is its own transient user unit, so `systemctl is-active` is the
# exact state and a waybar/launcher restart cannot kill it mid-file.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.whisper-cpp;

  # Upstream GGML weights from https://huggingface.co/ggerganov/whisper.cpp
  # Add new entries by running:
  #   nix hash file --type sha256 --base32 <local-copy>
  # then `nix store add-file <local-copy>` to seed the store without redownload.
  # Pinned to one HF revision so a re-upload under /resolve/main/ cannot
  # break a clean rebuild against a stale hash.
  hfRevision = "5359861c739e955e79d9a303bcbc70fb988958b1";
  knownModels = {
    "large-v3"  = "1qnijhsv47x1vx2vixy4jr8n0k6q8ham9ggrqh1m53dr82s85lb4";
    "medium.en" = "0mj3vbvaiyk5x2ids9zlp2g94a01l4qar9w109qcg3ikg0sfjdyc";
  };

  fetchModel = name: pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/${hfRevision}/ggml-${name}.bin";
    sha256 = knownModels.${name};
  };

  whisperPkg =
    if cfg.cuda
    then pkgs.whisper-cpp.override { cudaSupport = true; }
    else pkgs.whisper-cpp;

  modelFiles = lib.listToAttrs (map (m: {
    name = "${cfg.modelsDir}/ggml-${m}.bin";
    value = { source = fetchModel m; };
  }) cfg.models);

  # Push-to-talk toggle. All state transitions run under one flock so a
  # double press cannot start two recorders or stop one that is still
  # finalising. States: idle -> recording (unit active) -> transcribing
  # (marker file) -> idle.
  dictateScript = pkgs.writeShellScriptBin "whisper-dictate" ''
    set -euo pipefail

    RUN="''${XDG_RUNTIME_DIR:-/tmp}/whisper-dictate"
    mkdir -p "$RUN"
    UNIT="whisper-dictate-rec"
    WAV="$RUN/rec.wav"
    BUSY="$RUN/transcribing"
    FOCUS="$RUN/focus"
    MODEL="${cfg.modelsDir}/ggml-${cfg.dictate.model}.bin"
    MIN_BYTES=16044   # 44-byte WAV header + 0.5 s of 16 kHz s16 mono

    notify() { ${pkgs.libnotify}/bin/notify-send -t "$1" "$2" "''${3:-}"; }

    exec 9>"$RUN/lock"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      exit 0   # a transition is already in progress; ignore the press
    fi

    if [ -e "$BUSY" ]; then
      notify 2000 "Dictation busy" "Still transcribing the last take."
      exit 0
    fi

    # ---- recording -> transcribe ----------------------------------------
    if systemctl --user is-active --quiet "$UNIT.service"; then
      systemctl --user kill --signal=SIGINT "$UNIT.service"
      for _ in $(seq 1 50); do
        STATE=$(systemctl --user is-active "$UNIT.service" 2>/dev/null || true)
        [[ "$STATE" == "active" || "$STATE" == "deactivating" ]] || break
        sleep 0.1
      done
      touch "$BUSY"
      trap 'rm -f "$BUSY"' EXIT

      SIZE=$(stat -c %s "$WAV" 2>/dev/null || echo 0)
      if [ "$SIZE" -lt "$MIN_BYTES" ]; then
        notify 3000 "Dictation" "Too short — nothing transcribed."
        exit 0
      fi

      notify 2000 "Transcribing…" ""
      OUT="$RUN/out"
      rm -f "$OUT.txt"
      ${whisperPkg}/bin/whisper-cli -m "$MODEL" -f "$WAV" -otxt -of "$OUT" -np >/dev/null 2>&1 || true

      # One line, printable characters only: newlines would become Return
      # key events under wtype, and control bytes have no business here.
      TEXT=$(tr -d '\000-\010\013-\037\177' < "$OUT.txt" 2>/dev/null \
             | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//' || true)
      if [ -z "$TEXT" ]; then
        notify 3000 "Dictation" "No speech recognised."
        exit 0
      fi

      printf '%s' "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy

      # Type only into the window that had focus when recording started;
      # otherwise the text stays on the clipboard and the notice says so.
      NOW=$(hyprctl activewindow -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.address // empty' || true)
      THEN=$(cat "$FOCUS" 2>/dev/null || true)
      if [ -n "$NOW" ] && [ "$NOW" = "$THEN" ]; then
        ${pkgs.wtype}/bin/wtype -- "$TEXT" || true
        notify 4000 "Dictated" "$TEXT"
      else
        notify 5000 "Dictated (clipboard only — focus moved)" "$TEXT"
      fi
      exit 0
    fi

    # ---- idle -> recording ------------------------------------------------
    if [ ! -f "$MODEL" ]; then
      notify 5000 "Dictation model missing" "$MODEL — add ${cfg.dictate.model} to hwc.home.apps.whisper-cpp.models"
      exit 1
    fi
    rm -f "$WAV"
    hyprctl activewindow -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.address // empty' > "$FOCUS" || true

    systemd-run --user --quiet --collect --unit="$UNIT" \
      ${pkgs.pipewire}/bin/pw-record --rate 16000 --channels 1 --format s16 "$WAV"
    notify 2000 "⏺ Listening" "Press again to stop"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.whisper-cpp = {
    enable = lib.mkEnableOption "whisper.cpp speech-to-text with declarative models";

    cuda = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build whisper-cpp with CUDA backend (NVIDIA GPUs only).";
    };

    models = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames knownModels));
      default = [ "medium.en" ];
      example = [ "large-v3" "medium.en" ];
      description = "GGML model names to install. Symlinked into modelsDir as ggml-<name>.bin.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/models/whisper";
      description = "Directory where model symlinks live. Absolute path.";
    };

    dictate = {
      enable = lib.mkEnableOption "whisper-dictate push-to-talk toggle (Hyprland bind SUPER+SHIFT+SPACE)";

      model = lib.mkOption {
        type = lib.types.enum (lib.attrNames knownModels);
        default = "medium.en";
        description = "Model used by whisper-dictate. Must be in `models`.";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ whisperPkg ]
      ++ lib.optionals cfg.dictate.enable [ dictateScript pkgs.wtype ];

    # home.file paths must be relative to $HOME — strip the prefix.
    home.file = lib.mapAttrs' (path: spec:
      lib.nameValuePair (lib.removePrefix "${config.home.homeDirectory}/" path) spec
    ) modelFiles;

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.dictate.enable -> lib.elem cfg.dictate.model cfg.models;
        message = "hwc.home.apps.whisper-cpp.dictate.model (${cfg.dictate.model}) must be listed in hwc.home.apps.whisper-cpp.models.";
      }
    ];
  };
}
