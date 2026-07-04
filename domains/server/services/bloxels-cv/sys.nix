# domains/server/services/bloxels-cv/sys.nix
#
# System-lane implementation: systemd path unit + oneshot service that runs
# bloxels-capture on each photo dropped into the watch directory.
#
# Layout inside watchPath (all within the Syncthing share, so results and
# archives sync back to the phone):
#   <photo>.jpg           dropped by the phone
#   results/<photo>/      grid.json + debug.png
#   done/<date>/          successfully processed photos
#   failed/<date>/        photos the pipeline rejected (markers not found, ...)
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.bloxelsCv;

  capture   = "${cfg.package}/bin/bloxels-capture";
  coreutils = "${pkgs.coreutils}/bin";

  processScript = pkgs.writeShellScript "bloxels-cv-process" ''
    set -euo pipefail

    WATCH="${cfg.watchPath}"
    CAPTURE="${capture}"
    COREUTILS="${coreutils}"

    processed=0
    for f in "$WATCH"/*.jpg "$WATCH"/*.jpeg "$WATCH"/*.png "$WATCH"/*.JPG "$WATCH"/*.JPEG "$WATCH"/*.PNG; do
      [ -f "$f" ] || continue

      base=$("$COREUTILS/basename" "$f")
      stem="''${base%.*}"
      curdate=$("$COREUTILS/date" +%Y-%m-%d)
      outdir="$WATCH/results/$stem"

      echo "Processing grid photo: $f"
      mkdir -p "$outdir"
      if "$CAPTURE" "$f" -o "$outdir" > "$outdir/log.txt" 2>&1; then
        mkdir -p "$WATCH/done/$curdate"
        "$COREUTILS/mv" "$f" "$WATCH/done/$curdate/"
        echo "Done: $outdir/grid.json"
      else
        mkdir -p "$WATCH/failed/$curdate"
        "$COREUTILS/mv" "$f" "$WATCH/failed/$curdate/"
        echo "FAILED (see $outdir/log.txt): $f"
      fi
      processed=$((processed + 1))
    done

    echo "bloxels-cv: processed $processed photo(s)"
  '';

in
{
  config = lib.mkIf cfg.enable {

    #==========================================================================
    # REQUIRED DIRECTORIES (pre-created so ReadWritePaths does not fail)
    #==========================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.watchPath}         0755 eric users -"
      "d ${cfg.watchPath}/results 0755 eric users -"
      "d ${cfg.watchPath}/done    0755 eric users -"
      "d ${cfg.watchPath}/failed  0755 eric users -"
    ];

    #==========================================================================
    # SYSTEMD PATH UNIT (inotify watcher)
    #==========================================================================
    systemd.paths.bloxels-cv = {
      description = "Watch for new Bloxels grid photos in phone inbox";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = cfg.watchPath;
        MakeDirectory = true;
      };
    };

    #==========================================================================
    # SYSTEMD SERVICE UNIT (oneshot processor)
    #==========================================================================
    systemd.services.bloxels-cv = {
      description = "Classify Bloxels grid photos via bloxels-capture";
      serviceConfig = {
        Type = "oneshot";
        User = "eric";
        Group = "users";
        ExecStart = processScript;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.watchPath ];
      };
    };
  };
}
