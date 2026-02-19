# domains/server/native/orchestration/audiobook-copier/parts/config.nix
#
# Systemd tmpfiles for audiobook copier state directory

{ config, lib, ... }:
let
  cfg = config.hwc.server.native.orchestration.audiobookCopier;
in
{
  config = lib.mkIf cfg.enable {
    # Create state directory with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 eric users -"
    ];
  };
}
