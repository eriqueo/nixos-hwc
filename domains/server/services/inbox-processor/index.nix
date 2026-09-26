# domains/server/services/inbox-processor/index.nix
#
# Inbox Processor — systemd path-watcher + oneshot services for phone captures.
# Watches two directories via inotify; triggers Whisper STT (audio) or
# Tesseract OCR (screenshots); writes markdown to brain inbox.
#
# Namespace: hwc.server.services.inboxProcessor
{ config, lib, ... }:

let
  cfg = config.hwc.server.services.inboxProcessor;
in

{
  imports = [
    ./sys.nix
  ];

  # OPTIONS
  options.hwc.server.services.inboxProcessor = {
    enable = lib.mkEnableOption "inbox processor (Whisper audio transcription + Tesseract OCR for phone captures)";

    audioInboxPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to watch for new audio files from phone (.wav, .m4a, .mp3)";
    };

    screenshotsInboxPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to watch for new screenshot files from phone (.png, .jpg)";
    };

    brainInboxPath = lib.mkOption {
      type = lib.types.str;
      description = "Destination path in brain vault inbox for processed markdown files";
    };

    processedPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to move processed source files (organized by date)";
    };

    whisperUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString (config.hwc.server.ai.whisper.port or 11503)}";
      description = ''
        Base URL of a local or remote resident whisper-server. Use HTTPS for
        a remote host; only a loopback URL requires the local Whisper module.
        Transcription is POST <whisperUrl>/v1/audio/transcriptions. Replaced
        the per-file `whisper-cli --no-gpu base.en` on 2026-09-05: the resident
        server keeps the model loaded and runs on the GPU.
      '';
    };

    cleanup.enable = lib.mkEnableOption ''
      a DX2 pass over each voice transcript: a title, a short summary and
      action items go above the verbatim transcript. Fail-open — if DX2 is
      down, slow or returns junk, the note is written with the raw transcript
      exactly as before and `cleanup: raw` in its frontmatter. Endpoint facts
      come from hwc.server.ai.dx2. The transcript text leaves the box
    '';
  };

  # IMPLEMENTATION — delegated to sys.nix; this block holds assertions only.

  # VALIDATION
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.audioInboxPath != "";
        message = "hwc.server.services.inboxProcessor.audioInboxPath must be set";
      }
      {
        assertion = cfg.screenshotsInboxPath != "";
        message = "hwc.server.services.inboxProcessor.screenshotsInboxPath must be set";
      }
      {
        assertion = cfg.brainInboxPath != "";
        message = "hwc.server.services.inboxProcessor.brainInboxPath must be set";
      }
      {
        assertion = cfg.processedPath != "";
        message = "hwc.server.services.inboxProcessor.processedPath must be set";
      }
      {
        assertion = (config.hwc.server.ai.whisper.enable or false)
          || lib.hasPrefix "https://" cfg.whisperUrl;
        message = "inboxProcessor needs either enabled local Whisper or an explicit HTTPS whisperUrl.";
      }
      {
        assertion = cfg.cleanup.enable -> (config.hwc.server.ai ? dx2);
        message = "hwc.server.services.inboxProcessor.cleanup needs domains/server/native/ai/dx2/index.nix imported (it supplies the DX2 URL, model and key path).";
      }
    ];
  };
}
