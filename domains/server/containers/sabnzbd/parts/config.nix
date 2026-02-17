{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.sabnzbd;
  paths = config.hwc.paths;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/sabnzbd/config";
  iniPath = "${configPath}/sabnzbd.ini";

  # Generate category config as JSON for the Python script to consume
  categoriesJson = builtins.toJSON cfg.categories;

  # Script to enforce categories in sabnzbd.ini
  enforceCategoriesScript = pkgs.writeShellScript "sabnzbd-enforce-categories" ''
    set -euo pipefail

    if [ ! -f "${iniPath}" ]; then
      exit 0
    fi

    CATEGORIES_JSON='${categoriesJson}'

    ${pkgs.python3}/bin/python3 - "$CATEGORIES_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

ini_path = Path("${iniPath}")
categories = json.loads(sys.argv[1])

text = ini_path.read_text()

# For each category, ensure the dir is set correctly
for name, cat_cfg in categories.items():
    # Pattern to find the category section and its dir setting
    section_pattern = rf'\[\[{re.escape(name)}\]\].*?(?=\[\[|\Z)'
    section_match = re.search(section_pattern, text, re.DOTALL)

    if section_match:
        section = section_match.group(0)
        # Update or add dir setting
        if 'dir = ' in section:
            new_section = re.sub(r'dir = .*', f'dir = {cat_cfg["dir"]}', section)
        else:
            # Add dir after name line
            new_section = re.sub(r'(name = \w+)', rf'\1\ndir = {cat_cfg["dir"]}', section)
        text = text[:section_match.start()] + new_section + text[section_match.end():]

ini_path.write_text(text)
PY
  '';

  enforceHostWhitelist = pkgs.writeShellScript "sabnzbd-host-whitelist" ''
    set -euo pipefail

    if [ ! -f "${iniPath}" ]; then
      exit 0
    fi

    ${pkgs.python3}/bin/python3 - <<'PY'
from pathlib import Path

ini_path = Path("${iniPath}")
text = ini_path.read_text()
lines = text.splitlines()

target_hosts = ["gluetun", "sabnzbd"]
updated = False
found = False
new_lines = []

for line in lines:
    if line.startswith("host_whitelist = "):
        found = True
        value = line.split("=", 1)[1].strip()
        items = [x.strip() for x in value.split(",") if x.strip()]
        for host in target_hosts:
            if host not in items:
                items.append(host)
                updated = True
        line = "host_whitelist = " + ", ".join(items)
    new_lines.append(line)

if not found:
    new_lines.append("host_whitelist = " + ", ".join(target_hosts))
    updated = True

if updated:
    ini_path.write_text("\n".join(new_lines) + "\n")
PY
  '';
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.server.containers.gluetun.enable;
        message = "SABnzbd with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = paths.hot != null;
        message = "SABnzbd requires hwc.paths.hot to be configured for downloads and events";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.sabnzbd = {
      image = cfg.image;
      autoStart = true;

      # Network configuration - use gluetun network namespace for VPN mode
      extraOptions = [
        "--memory=2g"
        "--cpus=1.0"
        "--memory-swap=4g"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ]
      ) ++ lib.optionals cfg.gpu.enable [
        "--device=/dev/dri:/dev/dri"
      ];

      # Environment variables
      environment = {
        PUID = "1000";  # eric UID
        PGID = "100";   # users GID (CRITICAL - users group is GID 100, not 1000!)
        TZ = config.time.timeZone or "America/Denver";
        # Set SABnzbd download directories
        SABNZBD_COMPLETE_DIR = "/downloads";
        SABNZBD_INCOMPLETE_DIR = "/config/incomplete";
      } // lib.optionalAttrs (cfg.network.mode == "vpn") {
        # When using VPN, SABnzbd runs on port 8085 inside container
        # but gluetun exposes it as 8081 externally
        SABNZBD_PORT = "8085";
      } // lib.optionalAttrs (cfg.network.mode != "vpn") {
        # When not using VPN, use the configured webPort directly
        SABNZBD_PORT = toString cfg.webPort;
      };

      # Port exposure - only when not using VPN (gluetun exposes ports)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      # Volume mounts - CRITICAL: events mount is required for automation pipeline
      volumes = [
        "${configPath}:/config"
        "${paths.hot.root}/downloads:/downloads"
        "${paths.hot.root}/events:/mnt/hot/events"  # CRITICAL for event processing
        "${config.hwc.paths.hot.downloads}/scripts:/config/scripts:ro"  # Post-processing scripts
      ];

      # Dependencies
      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-sabnzbd = {
      serviceConfig.ExecStartPre = [
        "+${enforceCategoriesScript}"
        "+${enforceHostWhitelist}"
      ];
      after = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" "mnt-hot.mount" ]
        else [ "hwc-media-network.service" "mnt-hot.mount" ];
      wants = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "hwc-media-network.service" ];
      requires = [ "mnt-hot.mount" ];
    };



    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
      cfg.webPort
    ];
  };
}
