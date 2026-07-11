# domains/server/services/inbox-processor/sys.nix
#
# System-lane implementation: systemd path units + oneshot services for
# phone capture processing (Whisper audio transcription + Tesseract OCR).
#
# NOTE on Nix string escaping in writeShellScript:
#   ${nix_expr}  = Nix interpolation (evaluated at build time)
#   $shell_var   = Shell variable (evaluated at runtime, no braces needed)
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.inboxProcessor;

  # Store paths — evaluated at Nix build time
  whispercli  = "${pkgs.whisper-cpp}/bin/whisper-cli";
  tesseractBin = "${pkgs.tesseract}/bin/tesseract";
  coreutils   = "${pkgs.coreutils}/bin";
  gnused      = "${pkgs.gnused}/bin/sed";

  #============================================================================
  # AUDIO PROCESSING SCRIPT (Whisper STT)
  #============================================================================
  processAudioScript = pkgs.writeShellScript "inbox-processor-audio" ''
    set -euo pipefail

    AUDIO_DIR="${cfg.audioInboxPath}"
    BRAIN_INBOX="${cfg.brainInboxPath}"
    PROCESSED_DIR="${cfg.processedPath}"
    MODELS_DIR="${cfg.whisperModelsDir}"
    MODEL_FILE="$MODELS_DIR/ggml-${cfg.whisperModel}.bin"
    WHISPER_CLI="${whispercli}"
    COREUTILS="${coreutils}"
    SED="${gnused}"

    # Ensure output directories exist
    mkdir -p "$BRAIN_INBOX"

    processed=0
    for f in "$AUDIO_DIR"/*.wav "$AUDIO_DIR"/*.m4a "$AUDIO_DIR"/*.mp3 "$AUDIO_DIR"/*.ogg "$AUDIO_DIR"/*.flac; do
      [ -f "$f" ] || continue

      slug=$("$COREUTILS/basename" "$f" | "$SED" 's/\.[^.]*$//' | "$SED" 's/[^[:alnum:]_-]/-/g')
      curdate=$("$COREUTILS/date" +%Y-%m-%d)
      outfile="$BRAIN_INBOX/$curdate-audio-$slug.md"

      # Skip if already processed (output file exists)
      [ -f "$outfile" ] && continue

      echo "Processing audio: $f"

      transcript_text="(transcript unavailable)"
      if [ -f "$MODEL_FILE" ] && [ -x "$WHISPER_CLI" ]; then
        tmpdir=$("$COREUTILS/mktemp" -d)
        # whisper-cli flags: -m model, -f file, -otxt output-txt, -of output-file-prefix, -np no-prints
        "$WHISPER_CLI" \
          --no-gpu \
          -m "$MODEL_FILE" \
          -f "$f" \
          -otxt \
          -of "$tmpdir/transcript" \
          -np 2>/dev/null || true

        if [ -f "$tmpdir/transcript.txt" ]; then
          transcript_text=$("$COREUTILS/cat" "$tmpdir/transcript.txt")
        fi
        "$COREUTILS/rm" -rf "$tmpdir"
      else
        echo "WARNING: Whisper model not found at $MODEL_FILE -- writing stub"
      fi

      # Write markdown to brain inbox
      printf '%s\n' \
        "---" \
        "title: \"Audio capture $slug\"" \
        "created: \"$curdate\"" \
        "updated: \"$curdate\"" \
        "tags: [capture, audio, phone]" \
        "status: draft" \
        "source: phone-audio" \
        "original: \"$f\"" \
        "---" \
        "" \
        "# Audio Capture: $slug" \
        "" \
        "$transcript_text" \
        > "$outfile"

      # Move processed file to dated archive
      mkdir -p "$PROCESSED_DIR/$curdate"
      "$COREUTILS/mv" "$f" "$PROCESSED_DIR/$curdate/"
      echo "Done: $outfile"
      processed=$((processed + 1))
    done

    echo "inbox-processor-audio: processed $processed file(s)"
  '';

  #============================================================================
  # SCREENSHOT PROCESSING SCRIPT (Tesseract OCR)
  #============================================================================
  processScreenshotScript = pkgs.writeShellScript "inbox-processor-screenshots" ''
    set -euo pipefail

    SCREENSHOTS_DIR="${cfg.screenshotsInboxPath}"
    BRAIN_INBOX="${cfg.brainInboxPath}"
    PROCESSED_DIR="${cfg.processedPath}"
    TESSERACT="${tesseractBin}"
    COREUTILS="${coreutils}"
    SED="${gnused}"

    # Ensure output directories exist
    mkdir -p "$BRAIN_INBOX"

    processed=0
    for f in "$SCREENSHOTS_DIR"/*.png "$SCREENSHOTS_DIR"/*.jpg "$SCREENSHOTS_DIR"/*.jpeg; do
      [ -f "$f" ] || continue

      slug=$("$COREUTILS/basename" "$f" | "$SED" 's/\.[^.]*$//' | "$SED" 's/[^[:alnum:]_-]/-/g')
      curdate=$("$COREUTILS/date" +%Y-%m-%d)
      outfile="$BRAIN_INBOX/$curdate-screenshot-$slug.md"

      # Skip if already processed
      [ -f "$outfile" ] && continue

      echo "Processing screenshot: $f"

      ocr_text="(OCR unavailable)"
      if [ -x "$TESSERACT" ]; then
        tmpdir=$("$COREUTILS/mktemp" -d)
        "$TESSERACT" "$f" "$tmpdir/ocr" 2>/dev/null || true

        if [ -f "$tmpdir/ocr.txt" ]; then
          ocr_text=$("$COREUTILS/cat" "$tmpdir/ocr.txt")
        fi
        "$COREUTILS/rm" -rf "$tmpdir"
      fi

      # Write markdown to brain inbox
      printf '%s\n' \
        "---" \
        "title: \"Screenshot capture $slug\"" \
        "created: \"$curdate\"" \
        "updated: \"$curdate\"" \
        "tags: [capture, screenshot, phone]" \
        "status: draft" \
        "source: phone-screenshot" \
        "original: \"$f\"" \
        "---" \
        "" \
        "# Screenshot Capture: $slug" \
        "" \
        "$ocr_text" \
        > "$outfile"

      # Move processed file to dated archive
      mkdir -p "$PROCESSED_DIR/$curdate"
      "$COREUTILS/mv" "$f" "$PROCESSED_DIR/$curdate/"
      echo "Done: $outfile"
      processed=$((processed + 1))
    done

    echo "inbox-processor-screenshots: processed $processed file(s)"
  '';

in
{
  config = lib.mkIf cfg.enable {

    #==========================================================================
    # SYSTEM PACKAGES
    #==========================================================================
    environment.systemPackages = [
      pkgs.whisper-cpp   # whisper-cli binary
      pkgs.tesseract     # tesseract OCR binary
    ];

    #==========================================================================
    # WHISPER MODEL DIRECTORY
    #==========================================================================
    system.activationScripts.whisper-models-dir = lib.stringAfter [ "users" ] ''
      mkdir -p ${cfg.whisperModelsDir}
      chown eric:users ${cfg.whisperModelsDir}
      chmod 755 ${cfg.whisperModelsDir}
    '';

    #==========================================================================
    # REQUIRED DIRECTORIES (pre-created so ReadWritePaths does not fail)
    #==========================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.audioInboxPath}       0755 eric users -"
      "d ${cfg.screenshotsInboxPath} 0755 eric users -"
      "d ${cfg.brainInboxPath}       0755 eric users -"
      "d ${cfg.processedPath}        0755 eric users -"
    ];

    #==========================================================================
    # SYSTEMD PATH UNITS (inotify watchers)
    #==========================================================================
    systemd.paths = {
      inbox-processor-audio = {
        description = "Watch for new audio files in phone inbox";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = cfg.audioInboxPath;
          MakeDirectory = true;
        };
      };

      inbox-processor-screenshots = {
        description = "Watch for new screenshot files in phone inbox";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = cfg.screenshotsInboxPath;
          MakeDirectory = true;
        };
      };
    };

    #==========================================================================
    # SYSTEMD SERVICE UNITS (oneshot processors)
    #==========================================================================
    systemd.services = {
      inbox-processor-audio = {
        description = "Process audio files from phone inbox via Whisper STT";
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce "eric";
          Group = "users";
          ExecStart = processAudioScript;
          StateDirectory = "inbox-processor";
          # Security hardening (minimal — whisper-cpp needs full tmp access)
          NoNewPrivileges = true;
          ReadWritePaths = [
            cfg.audioInboxPath
            cfg.brainInboxPath
            cfg.processedPath
            cfg.whisperModelsDir
            "/var/lib/inbox-processor"
          ];
        };
      };

      inbox-processor-screenshots = {
        description = "Process screenshot files from phone inbox via Tesseract OCR";
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce "eric";
          Group = "users";
          ExecStart = processScreenshotScript;
          StateDirectory = "inbox-processor";
          # Security hardening (minimal — tesseract needs standard tmp access)
          NoNewPrivileges = true;
          ReadWritePaths = [
            cfg.screenshotsInboxPath
            cfg.brainInboxPath
            cfg.processedPath
            "/var/lib/inbox-processor"
          ];
        };
      };
    };
  };
}
