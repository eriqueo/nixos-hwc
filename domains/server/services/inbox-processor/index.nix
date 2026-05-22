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

# OPTIONS
{
  imports = [
    ./options.nix
    ./sys.nix
  ];

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
