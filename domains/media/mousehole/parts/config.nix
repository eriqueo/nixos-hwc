# domains/media/mousehole/parts/config.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.mousehole;
  appsRoot = config.hwc.paths.apps.root;
  dataPath = "${appsRoot}/mousehole/data";

  snapshotPath = "/var/lib/backups/mousehole/state.json";
  # CRITICAL: one last-good JSON snapshot and one bounded pending slot. A racing,
  # malformed or missing live file aborts backup rather than publishing bad state.
  snapshot = pkgs.writeScript "mousehole-state-snapshot" ''#!${pkgs.python3}/bin/python3
    import json, os, pathlib, sys
    os.umask(0o077)
    source, destination = map(pathlib.Path, sys.argv[1:])
    def read():
        with source.open('rb') as f:
            data = f.read(1048577)
        if len(data) > 1048576:
            raise ValueError('Mousehole state exceeds 1 MiB snapshot bound')
        return data
    data = read()
    state = json.loads(data)
    if not isinstance(state, dict) or not isinstance(state.get('currentCookie'), str) or not state['currentCookie']:
        raise ValueError('Mousehole state must preserve a configured credential')
    if read() != data:
        raise RuntimeError('Mousehole state changed during snapshot; prior snapshot retained')
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    pending = destination.with_suffix('.pending')
    try:
        with pending.open('wb') as f:
            os.fchmod(f.fileno(), 0o600)
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(pending, destination)
    finally:
        pending.unlink(missing_ok=True)
  '';

  # Script to ensure mousehole data directory exists
  ensureConfig = pkgs.writeShellScript "ensure-mousehole-config" ''
    set -euo pipefail

    DATA_DIR="${dataPath}"

    # Create data directory if it doesn't exist
    mkdir -p "$DATA_DIR"
    chown 1000:100 "$DATA_DIR"
  '';
in
{
  config = lib.mkIf cfg.enable {
    system.build.mouseholeStateSnapshot = snapshot;
    # /var/lib/backups is already covered by the enabled Borg job. Use its
    # existing producer/lock/archive path instead of a second backup worker.
    hwc.data.borg.preBackupScript = lib.mkIf config.hwc.data.borg.enable (lib.mkAfter ''
      ${snapshot} ${lib.escapeShellArg "${dataPath}/state.json"} ${lib.escapeShellArg snapshotPath}
    '');

    # Systemd service dependencies for mousehole container
    systemd.services."podman-mousehole" = {
      serviceConfig.ExecStartPre = [
        "+${ensureConfig}"
      ];
      after = [
        "podman-gluetun.service"
      ];
      requires = [ "podman-gluetun.service" ];
      bindsTo = [ "podman-gluetun.service" ];
      partOf = [ "podman-gluetun.service" ];
    };
  };
}
