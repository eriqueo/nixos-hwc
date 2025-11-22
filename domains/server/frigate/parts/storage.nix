# domains/server/frigate/parts/storage.nix
#
# Frigate Storage Pruning
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.frigate-storage-prune = {
      description = "Frigate storage pruning - maintain ${toString cfg.storage.maxSizeGB}GB cap";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      script = ''
        FRIGATE_MEDIA="${cfg.storage.mediaPath}"
        TARGET_SIZE_GB=${toString cfg.storage.maxSizeGB}

        get_size_gb() {
          if [[ -d "$1" ]]; then
            du -s "$1" | awk '{print int($1/1024/1024)}'
          else
            echo "0"
          fi
        }

        if [[ ! -d "$FRIGATE_MEDIA" ]]; then
          echo "Frigate media directory not found: $FRIGATE_MEDIA"
          exit 0
        fi

        current_size=$(get_size_gb "$FRIGATE_MEDIA")
        echo "Current size: $current_size GB, target: $TARGET_SIZE_GB GB"

        if [[ $current_size -le $TARGET_SIZE_GB ]]; then
          echo "Storage under limit"
          exit 0
        fi

        # Remove oldest dated directories
        removed=0
        while [[ $(get_size_gb "$FRIGATE_MEDIA") -gt $TARGET_SIZE_GB ]] && [[ $removed -lt 50 ]]; do
          oldest=$(find "$FRIGATE_MEDIA" -type d -name "????-??-??" | sort | head -1)
          if [[ -z "$oldest" ]]; then
            break
          fi
          echo "Removing: $oldest"
          rm -rf "$oldest"
          ((removed++))
        done

        echo "Removed $removed directories. New size: $(get_size_gb "$FRIGATE_MEDIA") GB"

        ${lib.optionalString cfg.monitoring.prometheus.enable ''
        if [[ -d "${cfg.monitoring.prometheus.textfilePath}" ]]; then
          {
            echo "# TYPE frigate_storage_size_bytes gauge"
            echo "frigate_storage_size_bytes $(( $(get_size_gb "$FRIGATE_MEDIA") * 1024 * 1024 * 1024 ))"
          } > ${cfg.monitoring.prometheus.textfilePath}/frigate_storage.prom.$$
          mv ${cfg.monitoring.prometheus.textfilePath}/frigate_storage.prom.$$ ${cfg.monitoring.prometheus.textfilePath}/frigate_storage.prom
        fi
        ''}
      '';

      startAt = cfg.storage.pruneSchedule;
      path = with pkgs; [ gawk coreutils findutils ];
    };
  };
}
