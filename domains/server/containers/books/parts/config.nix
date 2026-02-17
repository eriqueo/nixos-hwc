{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.books;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/books/config";
  iniPath = "${configPath}/config.ini";

  # Script to ensure http_root is set in LazyLibrarian config
  enforceHttpRoot = pkgs.writeShellScript "lazylibrarian-http-root" ''
    set -euo pipefail

    CONFIG_DIR="${configPath}"
    INI_PATH="${iniPath}"
    HTTP_ROOT="${cfg.httpRoot}"

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"

    # If config doesn't exist, create minimal one
    if [ ! -f "$INI_PATH" ]; then
      cat > "$INI_PATH" << EOF
[GENERAL]
imp_preflang = eng, English, en-US, en, en-GB
ebook_dir = /books
download_dir = /downloads
http_root = $HTTP_ROOT

[LOGGING]
logdir = /config/log

[POSTPROCESS]
audiobook_dest_folder = \$Author/\$Title
EOF
      chown 1000:100 "$INI_PATH"
      exit 0
    fi

    # Config exists - ensure http_root is set correctly
    ${pkgs.python3}/bin/python3 - <<PY
from pathlib import Path
import re

ini_path = Path("$INI_PATH")
http_root = "$HTTP_ROOT"
text = ini_path.read_text()
lines = text.splitlines()

updated = False
found = False
new_lines = []

for line in lines:
    if line.strip().startswith("http_root"):
        found = True
        current = line.split("=", 1)[1].strip() if "=" in line else ""
        if current != http_root:
            line = f"http_root = {http_root}"
            updated = True
    new_lines.append(line)

# If http_root not found, add it after [GENERAL] section
if not found:
    final_lines = []
    for line in new_lines:
        final_lines.append(line)
        if line.strip() == "[GENERAL]":
            final_lines.append(f"http_root = {http_root}")
            updated = True
    new_lines = final_lines

if updated:
    ini_path.write_text("\n".join(new_lines) + "\n")
    print(f"Updated http_root to: {http_root}")
else:
    print(f"http_root already set to: {http_root}")
PY
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Systemd service dependencies for books container
    systemd.services."podman-books" = {
      serviceConfig.ExecStartPre = [
        "+${enforceHttpRoot}"
      ];
      after = [
        "network-online.target"
        "init-media-network.service"
        "agenix.service"
        "mnt-hot.mount"
      ];
      wants = [
        "network-online.target"
        "agenix.service"
      ];
      requires = [ "mnt-hot.mount" ];
    };
  };
}
