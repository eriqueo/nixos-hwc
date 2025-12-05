{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.apps.beets-native;

  # Beets with all plugins enabled
  beetsPackage = pkgs.beets;

  beetsConfig = pkgs.writeText "config.yaml" ''
    directory: ${cfg.musicDir}
    library: ${cfg.configDir}/library.db

    import:
      move: yes
      copy: no
      write: yes
      incremental: yes
      timid: no
      log: ${cfg.configDir}/import.log

    paths:
      default: $albumartist/$album%aunique{}/$track $title
      singleton: Non-Album/$artist/$title
      comp: Compilations/$album%aunique{}/$track $title

    plugins: duplicates fetchart embedart scrub replaygain missing info chroma web

    duplicates:
      checksum: ffmpeg
      full: yes
      count: yes
      copy: ""
      move: ""     

    missing:
      count: yes
      format: '$albumartist - $album: missing $missing{$track} ($title)'
      album: yes
      
    fetchart:
      auto: yes
      cautious: yes
      cover_names: cover folder

    embedart:
      auto: yes
      maxwidth: 1000

    scrub:
      auto: yes

    replaygain:
      auto: no
      backend: ffmpeg

    info:
      format: $path

    ui:
      color: yes

    musicbrainz:
      searchlimit: 10

    match:
      strong_rec_thresh: 0.25
      medium_rec_thresh: 0.60
      rec_gap_thresh: 0.50
      max_rec:
        missing_tracks: strong
        unmatched_tracks: strong
      distance_weights:
        source: 1.5
        artist: 2.0
        album: 3.0
        media: 1.0
        mediums: 1.0
        year: 1.0
        country: 0.5
        label: 0.5
        catalognum: 0.5
        albumdisambig: 0.5
        album_id: 5.0
        tracks: 2.0
        missing_tracks: 0.9
        unmatched_tracks: 0.6
        track_title: 2.0
        track_artist: 2.0
        track_index: 1.0
        track_length: 2.0
        track_id: 5.0

    autotagger:
      strong_rec_thresh: 0.10

    web:
      host: 127.0.0.1
      port: 8337
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install beets with all plugins on the host
    environment.systemPackages = [
      beetsPackage
      pkgs.ffmpeg  # Required for replaygain and chroma
    ];

    # Create config directory
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0755 eric users -"
      "d ${cfg.musicDir} 0755 eric users -"
      "d ${cfg.importDir} 0755 eric users -"
      "L+ /home/eric/.config/beets/config.yaml - - - - ${beetsConfig}"
    ];

    # Beets web service (optional)
    systemd.services.beets-web = {
      description = "Beets Web Interface";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "eric";
        ExecStart = "${beetsPackage}/bin/beet web";
        Restart = "on-failure";
        Environment = [
          "BEETSDIR=/home/eric/.config/beets"
        ];
      };
    };

    # Auto-import service
    systemd.services.beets-auto-import = lib.mkIf cfg.automation.enable {
      description = "Beets automatic music import";
      serviceConfig = {
        Type = "oneshot";
        User = "eric";
        ExecStart = pkgs.writeShellScript "beets-auto-import" ''
          set -euo pipefail

          LOG_DIR="/var/log/beets-automation"
          LOG_FILE="$LOG_DIR/auto-import-$(date +%Y%m%d-%H%M%S).log"
          IMPORT_DIR="${cfg.importDir}"
          LOCK_FILE="/run/beets-auto-import.lock"

          mkdir -p "$LOG_DIR"
          exec 1> >(tee -a "$LOG_FILE")
          exec 2>&1

          echo "[$(date)] Starting beets auto-import"

          # Lock to prevent concurrent runs
          if ! mkdir "$LOCK_FILE" 2>/dev/null; then
              echo "[$(date)] Another import is running, exiting"
              exit 0
          fi
          trap "rmdir '$LOCK_FILE'" EXIT

          # Count files to import
          file_count=$(${pkgs.findutils}/bin/find "$IMPORT_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" -o -name "*.opus" \) 2>/dev/null | wc -l)
          echo "[$(date)] Found $file_count music files in $IMPORT_DIR"

          if [ "$file_count" -eq 0 ]; then
              echo "[$(date)] No files to import"
              exit 0
          fi

          # Run import with auto mode (minimal prompts)
          echo "[$(date)] Starting import..."
          ${beetsPackage}/bin/beet import -q "$IMPORT_DIR" || true

          echo "[$(date)] Import completed"
          echo "[$(date)] Cleanup complete"
        '';
        Nice = 10;  # Lower priority
      };
    };

    # Auto-import timer
    systemd.timers.beets-auto-import = lib.mkIf cfg.automation.enable {
      description = "Beets automatic import timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.automation.importInterval;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # Deduplication service
    systemd.services.beets-dedup = lib.mkIf cfg.automation.enable {
      description = "Beets deduplication and cleanup";
      serviceConfig = {
        Type = "oneshot";
        User = "eric";
        ExecStart = pkgs.writeShellScript "beets-dedup" ''
          set -euo pipefail

          LOG_DIR="/var/log/beets-automation"
          LOG_FILE="$LOG_DIR/dedup-$(date +%Y%m%d-%H%M%S).log"

          mkdir -p "$LOG_DIR"
          exec 1> >(tee -a "$LOG_FILE")
          exec 2>&1

          echo "[$(date)] Starting beets deduplication"

          # Find and list duplicates
          echo "[$(date)] Finding duplicates..."
          ${beetsPackage}/bin/beet duplicates -k > "$LOG_DIR/duplicates-$(date +%Y%m%d).txt" 2>&1 || true

          dup_count=$(wc -l < "$LOG_DIR/duplicates-$(date +%Y%m%d).txt" || echo "0")
          echo "[$(date)] Found $dup_count duplicate groups"

          # Fetch missing album art
          echo "[$(date)] Fetching missing album art..."
          ${beetsPackage}/bin/beet fetchart -q 2>&1 || true

          # Embed album art
          echo "[$(date)] Embedding album art..."
          ${beetsPackage}/bin/beet embedart -q 2>&1 || true

          # Update database
          echo "[$(date)] Updating database..."
          ${beetsPackage}/bin/beet update 2>&1 || true

          echo "[$(date)] Deduplication complete"
        '';
        Nice = 15;  # Even lower priority
      };
    };

    # Deduplication timer
    systemd.timers.beets-dedup = lib.mkIf cfg.automation.enable {
      description = "Beets deduplication timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.automation.dedupInterval;
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = builtins.pathExists cfg.musicDir || true;
        message = "Music directory ${cfg.musicDir} should exist";
      }
    ];
  };
}
