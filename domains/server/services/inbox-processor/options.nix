# domains/server/services/inbox-processor/options.nix
#
# Inbox Processor options -- Whisper + Tesseract OCR for phone captures
# Namespace: hwc.server.services.inboxProcessor (matches folder: domains/server/services/inbox-processor/)
{ lib, ... }:
{
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
}
