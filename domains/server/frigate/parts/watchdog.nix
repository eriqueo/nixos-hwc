# domains/server/frigate/parts/watchdog.nix
#
# Frigate Camera Health Monitoring
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;
in
{
  config = lib.mkIf (cfg.enable && cfg.monitoring.watchdog.enable) {
    systemd.services.frigate-camera-watchdog = {
      description = "Frigate camera health monitoring";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      script = ''
        FRIGATE_API="http://localhost:${toString cfg.settings.port}/api"
        MAX_RETRIES=3
        RETRY_DELAY=5

        # Wait for Frigate API to be ready with retries
        check_api_ready() {
          for i in $(seq 1 $MAX_RETRIES); do
            if ${pkgs.curl}/bin/curl -sf "$FRIGATE_API/stats" >/dev/null 2>&1; then
              return 0
            fi
            if [[ $i -lt $MAX_RETRIES ]]; then
              echo "Frigate API not ready, retrying in $RETRY_DELAY seconds... (attempt $i/$MAX_RETRIES)"
              sleep $RETRY_DELAY
            fi
          done
          echo "Frigate API not responding after $MAX_RETRIES attempts. Service may be starting or down."
          return 1
        }

        # Check if API is ready first
        if ! check_api_ready; then
          # Gracefully handle Frigate not being ready (e.g., during restart)
          # Don't fail the service, just log and exit
          echo "Skipping camera health check - Frigate API unavailable"
          exit 0
        fi

        check_camera() {
          local camera="$1"
          local stats
          if stats=$(${pkgs.curl}/bin/curl -s "$FRIGATE_API/stats" 2>/dev/null); then
            local fps
            fps=$(echo "$stats" | ${pkgs.jq}/bin/jq -r ".cameras[\"$camera\"].camera_fps // 0" 2>/dev/null || echo "0")
            if [[ "$fps" != "0" && "$fps" != "null" ]]; then
              echo "$camera: $fps FPS (healthy)"
              return 0
            fi
          fi
          echo "$camera: offline or no data"
          return 1
        }

        healthy=0
        total=0
        for cam in cobra_cam_1 cobra_cam_2 cobra_cam_3; do
          ((total++))
          if check_camera "$cam"; then
            ((healthy++))
          fi
        done

        echo "Health check: $healthy/$total cameras healthy"

        ${lib.optionalString cfg.monitoring.prometheus.enable ''
        if [[ -d "${cfg.monitoring.prometheus.textfilePath}" ]]; then
          {
            echo "# TYPE frigate_cameras_healthy gauge"
            echo "frigate_cameras_healthy $healthy"
            echo "# TYPE frigate_cameras_total gauge"
            echo "frigate_cameras_total $total"
          } > ${cfg.monitoring.prometheus.textfilePath}/frigate_cameras.prom.$$
          mv ${cfg.monitoring.prometheus.textfilePath}/frigate_cameras.prom.$$ ${cfg.monitoring.prometheus.textfilePath}/frigate_cameras.prom
        fi
        ''}

        # Exit successfully - this is a monitoring script, not a critical service
        exit 0
      '';

      startAt = cfg.monitoring.watchdog.schedule;
      path = with pkgs; [ curl jq ];
    };
  };
}
