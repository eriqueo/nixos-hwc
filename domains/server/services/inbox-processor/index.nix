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

    whisperModel = lib.mkOption {
      type = lib.types.str;
      default = "base.en";
      description = "Whisper model to use (tiny.en, base.en, small.en, medium.en)";
    };

    whisperModelsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/whisper-models";
      description = "Directory where Whisper GGML model files are stored";
    };
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
        assertion = cfg.whisperModelsDir != "";
        message = "hwc.server.services.inboxProcessor.whisperModelsDir must be set";
      }
    ];
  };
}
