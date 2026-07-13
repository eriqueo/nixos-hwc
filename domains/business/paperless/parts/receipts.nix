# domains/business/paperless/parts/receipts.nix
#
# Receipt + statement intake plumbing:
#
#   paperless-imap-proxy — socat exposing Proton Bridge IMAP (loopback-only
#     127.0.0.1:1143) on the podman media-network gateway, so the paperless
#     container's built-in mail fetcher can poll mailboxes. podman1 is a
#     trusted firewall interface; the bind address only exists once the
#     media network is up (same late-appearance gotcha as PostgreSQL's
#     10.89.0.1 listener — see domains/data/databases).
#
#   paperless-receipts-mover — watches the phone-synced Syncthing folder
#     (receipts.mobileDir) and moves photo/PDF drops into the consume dir,
#     where paperless OCRs them. PathExistsGlob keeps firing while matching
#     files remain, so the mover must always empty the folder (it does —
#     everything matching moves out; non-matching files are left alone and
#     not matched by the globs, so no retrigger loop).
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.business.paperless;
  paths = config.hwc.paths;
  consumeDir = cfg.storage.consumeDir;

  receiptExts = [ "pdf" "jpg" "jpeg" "png" "heic" "webp" ];
  globsFor = dir: lib.concatMap (e: [ "${dir}/*.${e}" "${dir}/*.${lib.toUpper e}" ]) receiptExts;

  # MUST fully drain the watched folder before exiting: the PathExistsGlob
  # unit re-fires as long as a matching file exists, so a skip-and-exit
  # here loops the service into its start limit. Files still being written
  # (Syncthing temp→rename, direct copies) are waited out in-process.
  moverScript = pkgs.writeShellScript "paperless-receipts-mover" ''
    set -euo pipefail
    shopt -s nullglob nocaseglob
    moved=0
    for attempt in 1 2 3 4 5 6; do
      remaining=0
      for f in ${lib.concatMapStringsSep " " (e: "${cfg.receipts.mobileDir}/*.${e}") receiptExts}; do
        # Wait out files modified in the last 5 seconds (still syncing)
        if [ -n "$(find "$f" -newermt '-5 seconds' 2>/dev/null)" ]; then
          remaining=$((remaining+1))
          continue
        fi
        mv -n "$f" "${consumeDir}/receipt_$(date +%Y%m%d-%H%M%S)_$(basename "$f")"
        moved=$((moved+1))
      done
      [ "$remaining" -eq 0 ] && break
      sleep 5
    done
    echo "paperless-receipts-mover: moved $moved file(s) to consume."
  '';
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [

    (lib.mkIf cfg.mailIngest.enable {
      systemd.services.paperless-imap-proxy = {
        description = "Proton Bridge IMAP proxy for paperless mail ingest";
        after = [ "network-online.target" "init-media-network.service" "protonmail-bridge.service" ];
        wants = [ "network-online.target" "protonmail-bridge.service" ];
        requires = [ "init-media-network.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = ''
            ${pkgs.socat}/bin/socat \
              TCP-LISTEN:${toString cfg.mailIngest.port},bind=${cfg.mailIngest.gatewayAddr},fork,reuseaddr \
              TCP:127.0.0.1:${toString cfg.mailIngest.port}
          '';
          Restart = "on-failure";
          RestartSec = 10;
          User = lib.mkForce "eric";
          DynamicUser = false;
        };
      };
    })

    (lib.mkIf cfg.receipts.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.receipts.mobileDir} 0775 eric users - -"
      ];

      systemd.paths.paperless-receipts-mover = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExistsGlob = globsFor cfg.receipts.mobileDir;
          # Re-check while files linger (e.g. mover skipped a too-fresh file)
          TriggerLimitIntervalSec = "10s";
          TriggerLimitBurst = 20;
        };
      };

      systemd.services.paperless-receipts-mover = {
        description = "Move phone receipt drops into the paperless consume dir";
        # The drain loop makes rapid re-triggers legitimate (each run empties
        # the folder); don't let a burst of Syncthing arrivals wedge the unit.
        startLimitIntervalSec = 0;
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce "eric";
          Group = "users";
          ExecStart = moverScript;
        };
      };

      # Belt-and-braces sweep for files the path unit skipped (fresh-file
      # guard) — PathExistsGlob only re-fires on trigger events.
      systemd.timers.paperless-receipts-mover = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/15";
          Persistent = true;
        };
      };
    })
  ]);
}
