# domains/automation/mqtt/index.nix
#
# Mosquitto MQTT broker — lightweight message bus for service integration
# Used by Frigate for detection events, consumed by n8n workflows
#
# NAMESPACE: hwc.automation.mqtt.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.mqtt;
  paths = config.hwc.paths;

  # MQTT to webhook bridge script
  mqttWebhookBridge = pkgs.writeShellScript "mqtt-webhook-bridge" ''
    set -euo pipefail

    MQTT_HOST="127.0.0.1"
    MQTT_PORT="${toString cfg.port}"
    WEBHOOK_URL="${cfg.webhookBridge.webhookUrl}"
    TOPIC="${cfg.webhookBridge.topic}"

    echo "Starting MQTT-to-Webhook bridge"
    echo "  MQTT: $MQTT_HOST:$MQTT_PORT"
    echo "  Topic: $TOPIC"
    echo "  Webhook: $WEBHOOK_URL"

    ${pkgs.mosquitto}/bin/mosquitto_sub \
      -h "$MQTT_HOST" \
      -p "$MQTT_PORT" \
      -t "$TOPIC" \
      -v | while read -r line; do
        # Extract topic and payload (format: "topic payload")
        topic=$(echo "$line" | cut -d' ' -f1)
        payload=$(echo "$line" | cut -d' ' -f2-)

        # One request in flight; pipe backpressure bounds memory. QoS 0 remains
        # best effort. External POSTs are non-retriable: an ambiguous timeout
        # must not trigger a duplicate notification.
        if [ -n "$payload" ] && [ "$payload" != "$topic" ]; then
          ${lib.optionalString (cfg.webhookBridge.eventTypes != []) ''
            if ! ${pkgs.jq}/bin/jq -e --argjson types '${builtins.toJSON cfg.webhookBridge.eventTypes}' \
              '.type as $type | $types | index($type) != null' <<< "$payload" >/dev/null; then
              continue
            fi
          ''}
          event_id=$(${pkgs.jq}/bin/jq -c '.after.id // .id // "unknown"' <<< "$payload" 2>/dev/null || echo '"invalid-json"')
          if status=$(${pkgs.curl}/bin/curl --silent --show-error --fail \
            --connect-timeout 3 --max-time 15 -o /dev/null -w '%{http_code}' -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$WEBHOOK_URL"); then
            echo "event=$event_id outcome=accepted http=$status (delivery tracked by n8n)"
          else
            result=$?
            echo "event=$event_id outcome=failed http=$status curl_exit=$result retry=false" >&2
          fi
        fi
      done
  '';
in
{
  options.hwc.automation.mqtt = {
    enable = lib.mkEnableOption "Mosquitto MQTT broker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT broker port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/mosquitto";
      description = "Data directory for mosquitto persistence";
    };

    webhookBridge = {
      enable = lib.mkEnableOption "MQTT to webhook bridge for n8n";

      topic = lib.mkOption {
        type = lib.types.str;
        default = "frigate/events";
        description = "MQTT topic to subscribe to";
      };

      webhookUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:5678/webhook/frigate-events";
        description = "Webhook URL to forward messages to";
      };
      eventTypes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Forward only these JSON event types; empty forwards every payload";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use native NixOS mosquitto service (simpler than container for local-only broker)
    services.mosquitto = {
      enable = true;

      persistence = true;
      dataDir = cfg.dataDir;

      listeners = [
        {
          address = "127.0.0.1";
          port = cfg.port;
          omitPasswordAuth = true;
          settings.allow_anonymous = true;
          acl = [ "topic readwrite #" ];
        }
      ];
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 mosquitto mosquitto -"
    ];

    # Firewall - localhost only (services communicate internally)
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];

    # MQTT to webhook bridge service
    systemd.services.mqtt-webhook-bridge = lib.mkIf cfg.webhookBridge.enable {
      description = "MQTT to Webhook bridge for n8n";
      after = [ "mosquitto.service" "network.target" ];
      wants = [ "mosquitto.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${mqttWebhookBridge}";
        Restart = "always";
        RestartSec = 5;
        TimeoutStopSec = 20;
        User = "nobody";
        Group = "nogroup";
      };
    };
  };
}
