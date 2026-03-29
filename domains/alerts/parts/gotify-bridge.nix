# domains/alerts/parts/gotify-bridge.nix
#
# Alertmanager → gotify bridge service
#
# Receives Alertmanager webhook POSTs and forwards each alert
# as a formatted notification to the local gotify server.
#
# NAMESPACE: hwc.alerts.gotifyBridge.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.alerts.gotifyBridge;
  alertsCfg = config.hwc.alerts;

  bridgeScript = pkgs.writers.writePython3 "alertmanager-gotify-bridge" {
    flakeIgnore = [ "E501" "W503" ];
  } ''
    import json
    import http.server
    import urllib.request
    import sys
    import os
    import datetime

    GOTIFY_URL = sys.argv[1]
    LISTEN_PORT = int(sys.argv[2])
    TOKEN_FILE = sys.argv[3] if len(sys.argv) > 3 else None
    LOG_DIR = "/var/log/hwc/alerts"

    # ntfy priority (1-5) -> gotify priority (0-10)
    SEVERITY_PRIORITY = {
        "P5": 10,
        "P4": 7,
        "P3": 5,
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
            with open(f"{LOG_DIR}/gotify-bridge.log", "a") as f:
                f.write(line + "\n")
        except Exception:
            pass


    def read_token():
        if TOKEN_FILE and os.path.isfile(TOKEN_FILE):
            with open(TOKEN_FILE) as f:
                return f.read().strip()
        return ""


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
                priority = 3
            else:
                title = f"{emoji} {severity}: {summary}"
                priority = SEVERITY_PRIORITY.get(severity, 5)

            lines = []
            if description:
                lines.append(description)
            if instance:
                lines.append(f"Instance: {instance}")
            if category:
                lines.append(f"Category: {category}")
            lines.append(f"Status: {status}")
            message = "\n".join(lines)

            token = read_token()
            url = f"{GOTIFY_URL}/message?token={token}"

            payload = json.dumps({
                "title": title[:256],
                "message": message,
                "priority": priority,
            })

            req = urllib.request.Request(
                url,
                data=payload.encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )

            try:
                urllib.request.urlopen(req, timeout=10)
                log(f"Sent {status} alert: {alertname} ({severity})")
            except Exception as e:
                log(f"gotify POST failed for {alertname}: {e}")
                raise

        def log_message(self, format, *args):
            log(format % args)


    if __name__ == "__main__":
        server = http.server.HTTPServer(("127.0.0.1", LISTEN_PORT), AlertHandler)
        log(f"Listening on 127.0.0.1:{LISTEN_PORT}, forwarding to {GOTIFY_URL}")
        server.serve_forever()
  '';

in
{
  options.hwc.alerts.gotifyBridge = {
    enable = lib.mkEnableOption "Alertmanager to gotify bridge service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9095;
      description = "Port for the bridge HTTP server to listen on";
    };

    gotifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString alertsCfg.server.internalPort}";
      description = "Gotify server URL (e.g., http://localhost:2587)";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = alertsCfg.server.tokens.alertsFile;
      description = "Path to file containing gotify app token for alerts";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.alertmanager-gotify-bridge = {
      description = "Alertmanager to gotify notification bridge";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${bridgeScript} ${lib.escapeShellArg cfg.gotifyUrl} ${toString cfg.port} ${lib.optionalString (cfg.tokenFile != null) cfg.tokenFile}";
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
        message = "alertmanager-gotify-bridge requires the gotify server (hwc.alerts.server.enable = true)";
      }
    ];
  };
}
