# Readarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.readarr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/readarr/config";

  # Minimal pre-start: just ensure directory and URL base
  enforceScript = pkgs.writeShellScript "enforce-readarr-config" ''
    CONFIG_FILE="${configPath}/config.xml"
    mkdir -p "${configPath}"

    # Only set UrlBase if config exists (don't interfere with first-run setup)
    if [ -f "$CONFIG_FILE" ]; then
      ${pkgs.gnused}/bin/sed -i \
        -e 's|<UrlBase>[^<]*</UrlBase>|<UrlBase>/readarr</UrlBase>|' \
        "$CONFIG_FILE"
    fi
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-readarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-readarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-readarr".requires = [ "mnt-hot.mount" ];
    systemd.services."podman-readarr".serviceConfig.ExecStartPre = [ "+${enforceScript}" ];
  };
}
