# slskd Soulseek daemon container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.slskd;
  mediaNetworkName = "media-network";
  hotRoot = "/mnt/hot";

  # SLSKD configuration set
  slskdConfigSet = {
    debug = false;
    headless = false;
    remote_configuration = false;
    remote_file_management = false;

    web = {
      port = 5030;
      # No url_base - SLSKD runs on its own port, not as a subpath
      https = {
        disabled = true;
        port = 5031;
        force = false;
      };
      authentication = {
        disabled = false;
        username = "slskd-admin";
        password = "NpbG0Jcj4CP2h50arX6wtxFc5ju4PaPQ";
        jwt = {
          key = "Nd5g9X1AcVck7z7Q4Yq0IuULeQ7ci/Zu7++Lmcq7jOqF0e6ZbCvp5SmWVBN3EAVE";
          ttl = 604800000;
        };
      };
    };

    soulseek = {
      username = "eriqueok";
      password = "il0wwlm?";
      description = "A slskd user. https://github.com/slskd/slskd";
      listen_ip_address = "0.0.0.0";
      listen_port = 50300;
    };
  };

  yamlFormat = pkgs.formats.yaml {};
  slskdConfigFile = yamlFormat.generate "slskd.yml" slskdConfigSet;
in
{
  config = lib.mkIf cfg.enable {
    # Create SLSKD configuration directory
    systemd.tmpfiles.rules = [
      "d /var/lib/slskd 0755 root root -"
    ];

    # Create SLSKD configuration file
    environment.etc."slskd/slskd.yml" = {
      source = slskdConfigFile;
      mode = "0644";
    };

    # Container definition
    virtualisation.oci-containers.containers.slskd = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [
        "--network=${mediaNetworkName}"
      ];
      cmd = [ "--config" "/app/slskd.yml" ];
      ports = [
        "0.0.0.0:5031:5030"        # Web UI - expose directly on external interface
        "0.0.0.0:50300:50300/tcp"  # P2P port
      ];
      volumes = [
        "${hotRoot}/downloads/incomplete:/downloads/incomplete"
        "${hotRoot}/downloads/complete:/downloads/complete"
        "/etc/slskd/slskd.yml:/app/slskd.yml:ro"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = [ 50300 5031 ];

    # Service dependencies
    systemd.services."podman-slskd".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-slskd".wants = [ "network-online.target" ];
  };
}
