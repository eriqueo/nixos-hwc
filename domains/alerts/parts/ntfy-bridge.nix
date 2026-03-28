# domains/alerts/parts/ntfy-bridge.nix
#
# Alertmanager → ntfy bridge service
#
# Receives Alertmanager webhook POSTs and forwards each alert
# as a formatted notification to the local ntfy server.
#
# NAMESPACE: hwc.alerts.ntfyBridge.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.alerts.ntfyBridge;
  alertsCfg = config.hwc.alerts;

  bridgeScript = pkgs.writers.writePython3 "alertmanager-ntfy-bridge" {
    flakeIgnore = [ "E501" "W503" ];
  } ''
    import json
    import http.server
    import urllib.request
    import sys
    import os
    import datetime

    NTFY_URL = sys.argv[1]
    LISTEN_PORT = int(sys.argv[2])
    LOG_DIR = "/var/log/hwc/alerts"

    SEVERITY_PRIORITY = {
        "P5": "5",
        "P4": "4",
        "P3": "3",
    }

    SEVERITY_TAGS = {
        "P5": "rotating_light",
        "P4": "warning",
        "P3": "information_source",
    }

    STATUS_EMOJI = {
        "firing": "\U0001f534",
        "resolved": "\u2705",
    }


    def log(msg):
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{ts}] {msg}"
        print(line, file=sys.stderr, flush=True)
        try:
            os.makedirs(LOG_DIR, exist_ok=True)
            with open(f"{LOG_DIR}/ntfy-bridge.log", "a") as f:
                f.write(line + "\n")
        except Exception:
            pass


    class AlertHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)

            try:
                data = json.loads(body)
            except json.JSONDecodeError as e:
                log(f"Invalid JSON: {e}")
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Invalid JSON")
                return

            alerts = data.get("alerts", [])
            log(f"Received {len(alerts)} alert(s)")

            for alert in alerts:
                try:
                    self._forward_alert(alert)
                except Exception as e:
                    log(f"Failed to forward alert: {e}")

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")

        def _forward_alert(self, alert):
            labels = alert.get("labels", {})
            annotations = alert.get("annotations", {})
            status = alert.get("status", "unknown")

            alertname = labels.get("alertname", "Unknown")
            severity = labels.get("severity", "P3")
            instance = labels.get("instance", "")
            category = labels.get("category", "")
            summary = annotations.get("summary", alertname)
            description = annotations.get("description", "")

            emoji = STATUS_EMOJI.get(status, "\u2753")

            if status == "resolved":
                title = f"{emoji} RESOLVED: {summary}"
                priority = "2"
                tags = "white_check_mark"
            else:
                title = f"{emoji} {severity}: {summary}"
                priority = SEVERITY_PRIORITY.get(severity, "3")
                tags = SEVERITY_TAGS.get(severity, "bell")

            lines = []
            if description:
                lines.append(description)
            if instance:
                lines.append(f"Instance: {instance}")
            if category:
                lines.append(f"Category: {category}")
            lines.append(f"Status: {status}")
            message = "\n".join(lines)

            req = urllib.request.Request(
                NTFY_URL,
                data=message.encode("utf-8"),
            )
            req.add_header("Priority", priority)
            req.add_header("Tags", tags)
            req.add_unredirected_header(
                "Title",
                title[:256].encode("utf-8"),
            )

            try:
                urllib.request.urlopen(req, timeout=10)
                log(f"Sent {status} alert: {alertname} ({severity})")
            except Exception as e:
                log(f"ntfy POST failed for {alertname}: {e}")
                raise

        def log_message(self, format, *args):
            log(format % args)


    if __name__ == "__main__":
        server = http.server.HTTPServer(("127.0.0.1", LISTEN_PORT), AlertHandler)
        log(f"Listening on 127.0.0.1:{LISTEN_PORT}, forwarding to {NTFY_URL}")
        server.serve_forever()
  '';

in
{
  options.hwc.alerts.ntfyBridge = {
    enable = lib.mkEnableOption "Alertmanager to ntfy bridge service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9095;
      description = "Port for the bridge HTTP server to listen on";
    };

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString alertsCfg.server.port}/alerts";
      description = "ntfy server URL including topic (e.g., http://localhost:8080/hwc-alerts)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.alertmanager-ntfy-bridge = {
      description = "Alertmanager to ntfy notification bridge";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${bridgeScript} ${lib.escapeShellArg cfg.ntfyUrl} ${toString cfg.port}";
        Restart = "always";
        RestartSec = "5s";

        User = "eric";
        Group = "users";

        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/log/hwc/alerts" ];
      };
    };

    assertions = [
      {
        assertion = !cfg.enable || alertsCfg.server.enable;
        message = "alertmanager-ntfy-bridge requires the ntfy server (hwc.alerts.server.enable = true)";
      }
    ];
  };
}
