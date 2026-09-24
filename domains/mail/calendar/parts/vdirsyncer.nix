{ lib, cfg, radicalePair }:
let
  dataDir = "~/.local/share/vdirsyncer";

  # Pairs contributed by sibling modules (e.g. mail/tasks → VTODO/Reminders).
  # Kept in the same config so vdirsyncer has one config file + one timer.
  extraPairs = lib.concatStringsSep "\n" cfg.extraVdirsyncerPairs;
in
{
  config = ''
    [general]
    status_path = "${dataDir}/status/"

    ${radicalePair}
    ${extraPairs}
  '';
}
