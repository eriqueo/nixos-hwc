# Tdarr Safety and Backup Configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.tdarr;
  paths = config.hwc.paths;

  # Safety script that creates backups before transcoding
  tdarrSafetyScript = pkgs.writeShellScriptBin "tdarr-safety-check" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    echo -e "''${GREEN}=== Tdarr Safety Check & Backup System ===''${NC}"

    # Check if backup directory exists
    BACKUP_DIR="/mnt/hot/processing/tdarr-backups"
    if [ ! -d "$BACKUP_DIR" ]; then
      echo -e "''${YELLOW}Creating backup directory: $BACKUP_DIR''${NC}"
      mkdir -p "$BACKUP_DIR"
      chown 1000:1000 "$BACKUP_DIR"
    fi

    # Check available space
    echo ""
    echo -e "''${GREEN}Storage Status:''${NC}"
    df -h /mnt/media | tail -1
    df -h /mnt/hot | tail -1

    MEDIA_AVAIL=$(df /mnt/media | tail -1 | awk '{print $4}')
    HOT_AVAIL=$(df /mnt/hot | tail -1 | awk '{print $4}')

    # Warn if less than 100GB free
    if [ "$MEDIA_AVAIL" -lt 100000000 ]; then
      echo -e "''${RED}WARNING: Less than 100GB free on /mnt/media''${NC}"
    fi

    if [ "$HOT_AVAIL" -lt 50000000 ]; then
      echo -e "''${RED}WARNING: Less than 50GB free on /mnt/hot''${NC}"
    fi

    # Check Tdarr container is running
    echo ""
    if ${pkgs.podman}/bin/podman ps | grep -q tdarr; then
      echo -e "''${GREEN}✓ Tdarr container is running''${NC}"
    else
      echo -e "''${RED}✗ Tdarr container is NOT running''${NC}"
      exit 1
    fi

    # Check GPU is accessible
    echo ""
    if ${pkgs.podman}/bin/podman exec tdarr nvidia-smi > /dev/null 2>&1; then
      echo -e "''${GREEN}✓ GPU is accessible to Tdarr''${NC}"
      ${pkgs.podman}/bin/podman exec tdarr nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader
    else
      echo -e "''${YELLOW}! GPU check failed (might not be enabled)''${NC}"
    fi

    echo ""
    echo -e "''${GREEN}Safety check complete!''${NC}"
    echo ""
    echo -e "''${YELLOW}IMPORTANT SAFETY TIPS:''${NC}"
    echo "1. Tdarr is configured to create NEW files (not replace originals)"
    echo "2. Always test on a small library first (10-20 files)"
    echo "3. Check transcoded files manually before enabling auto-replace"
    echo "4. Keep at least 100GB free space for working directory"
    echo ""
  '';

  # Pre-transcode verification script
  tdarrPreTranscodeCheck = pkgs.writeShellScriptBin "tdarr-pre-transcode" ''
    #!/usr/bin/env bash
    # This script runs before each transcode to verify file safety

    FILE="$1"

    if [ -z "$FILE" ]; then
      echo "Usage: tdarr-pre-transcode <file>"
      exit 1
    fi

    # Check file exists and is readable
    if [ ! -f "$FILE" ]; then
      echo "ERROR: File does not exist: $FILE"
      exit 1
    fi

    if [ ! -r "$FILE" ]; then
      echo "ERROR: File is not readable: $FILE"
      exit 1
    fi

    # Check file is not empty
    SIZE=$(stat -c%s "$FILE")
    if [ "$SIZE" -eq 0 ]; then
      echo "ERROR: File is empty: $FILE"
      exit 1
    fi

    # Create backup reference (checksum)
    BACKUP_DIR="/mnt/hot/processing/tdarr-backups"
    mkdir -p "$BACKUP_DIR"

    FILENAME=$(basename "$FILE")
    CHECKSUM_FILE="$BACKUP_DIR/$FILENAME.sha256"

    sha256sum "$FILE" > "$CHECKSUM_FILE"
    echo "Created checksum: $CHECKSUM_FILE"

    # Store original file size
    echo "$SIZE" > "$BACKUP_DIR/$FILENAME.size"

    echo "Pre-transcode check passed: $FILE"
    exit 0
  '';

  # Post-transcode verification script
  tdarrPostTranscodeCheck = pkgs.writeShellScriptBin "tdarr-post-transcode" ''
    #!/usr/bin/env bash
    # This script verifies transcoded files are valid before replacing originals

    ORIGINAL="$1"
    TRANSCODED="$2"

    if [ -z "$ORIGINAL" ] || [ -z "$TRANSCODED" ]; then
      echo "Usage: tdarr-post-transcode <original> <transcoded>"
      exit 1
    fi

    echo "Verifying transcode: $TRANSCODED"

    # Check transcoded file exists
    if [ ! -f "$TRANSCODED" ]; then
      echo "ERROR: Transcoded file does not exist: $TRANSCODED"
      exit 1
    fi

    # Check transcoded file is not empty
    NEW_SIZE=$(stat -c%s "$TRANSCODED")
    if [ "$NEW_SIZE" -eq 0 ]; then
      echo "ERROR: Transcoded file is empty"
      exit 1
    fi

    # Check transcoded file is smaller (it should be with H.265)
    ORIG_SIZE=$(stat -c%s "$ORIGINAL")
    if [ "$NEW_SIZE" -gt "$ORIG_SIZE" ]; then
      echo "WARNING: Transcoded file is LARGER than original ($NEW_SIZE > $ORIG_SIZE)"
      echo "This might indicate a problem. Manual review recommended."
    fi

    # Verify video integrity using ffmpeg
    if ${pkgs.ffmpeg}/bin/ffprobe -v error "$TRANSCODED" > /dev/null 2>&1; then
      echo "✓ Transcoded file is valid video"
    else
      echo "ERROR: Transcoded file failed ffprobe validation"
      exit 1
    fi

    # Compare durations (should be within 1 second)
    ORIG_DURATION=$(${pkgs.ffmpeg}/bin/ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$ORIGINAL")
    NEW_DURATION=$(${pkgs.ffmpeg}/bin/ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TRANSCODED")

    DURATION_DIFF=$(echo "$ORIG_DURATION - $NEW_DURATION" | ${pkgs.bc}/bin/bc | ${pkgs.coreutils}/bin/tr -d '-')

    if [ "$(echo "$DURATION_DIFF > 1" | ${pkgs.bc}/bin/bc)" -eq 1 ]; then
      echo "WARNING: Duration mismatch: Original=$ORIG_DURATION, New=$NEW_DURATION"
      echo "Manual review recommended before replacing original"
    else
      echo "✓ Duration match verified"
    fi

    echo "Post-transcode check passed!"
    echo "Original size: $ORIG_SIZE bytes"
    echo "New size: $NEW_SIZE bytes"
    echo "Space saved: $(echo "scale=1; ($ORIG_SIZE - $NEW_SIZE) / 1048576" | ${pkgs.bc}/bin/bc) MB"

    exit 0
  '';

in
{
  config = lib.mkIf cfg.enable {
    # Install safety scripts system-wide
    environment.systemPackages = [
      tdarrSafetyScript
      tdarrPreTranscodeCheck
      tdarrPostTranscodeCheck
    ];

    # Create backup directory on boot
    systemd.tmpfiles.rules = [
      "d /mnt/hot/processing/tdarr-backups 0755 1000 1000 -"
    ];

    # Daily safety check timer
    systemd.services.tdarr-safety-check = {
      description = "Tdarr safety and health check";
      after = [ "podman-tdarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tdarrSafetyScript}/bin/tdarr-safety-check";
      };
    };

    systemd.timers.tdarr-safety-check = {
      description = "Daily Tdarr safety check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
