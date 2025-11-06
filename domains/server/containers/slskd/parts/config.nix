# slskd Soulseek daemon container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.slskd;
  mediaNetworkName = "media-network";
  hotRoot = "/mnt/hot";

  # Read secrets from agenix
  webUsername = lib.strings.removeSuffix "\n" (builtins.readFile config.age.secrets.slskd-web-username.path);
  webPassword = lib.strings.removeSuffix "\n" (builtins.readFile config.age.secrets.slskd-web-password.path);
  soulseekUsername = lib.strings.removeSuffix "\n" (builtins.readFile config.age.secrets.slskd-soulseek-username.path);
  soulseekPassword = lib.strings.removeSuffix "\n" (builtins.readFile config.age.secrets.slskd-soulseek-password.path);
  apiKey = lib.strings.removeSuffix "\n" (builtins.readFile config.age.secrets.slskd-api-key.path);

  # SLSKD configuration set
  slskdConfigSet = {
    debug = false;
    headless = false;
    remote_configuration = false;
    remote_file_management = false;

    web = {
      port = 5030;
      # SLSKD doesn't support subpaths - must run on dedicated port
      https = {
        disabled = true;
        port = 5031;
        force = false;
      };
      authentication = {
        disabled = false;
        username = webUsername;
        password = webPassword;
        jwt = {
          key = "Nd5g9X1AcVck7z7Q4Yq0IuULeQ7ci/Zu7++Lmcq7jOqF0e6ZbCvp5SmWVBN3EAVE";
          ttl = 604800000;
        };
        apiKeys = {
          soularr = apiKey;
        };
      };
    };

    directories = {
      downloads = "/downloads/music";
      incomplete = "/downloads/incomplete";
    };

    shares = {
      directories = [
        "[Downloads]/downloads/music"
        "[Library]/music"
      ];
    };

    soulseek = {
      username = soulseekUsername;
      password = soulseekPassword;
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
        "0.0.0.0:5031:5030"        # Web UI - SLSKD requires dedicated port
        "0.0.0.0:50300:50300/tcp"  # P2P port
      ];
      volumes = [
        "${hotRoot}/downloads/incomplete:/downloads/incomplete"
        "${hotRoot}/downloads/music:/downloads/music"
        "/mnt/media/music:/music:ro"
        "/etc/slskd/slskd.yml:/app/slskd.yml:ro"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
      };
    };

    # Firewall configuration - SLSKD requires dedicated port
    networking.firewall.allowedTCPPorts = [ 50300 5031 ];

    # Service dependencies
    systemd.services."podman-slskd".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-slskd".wants = [ "network-online.target" ];
  };
}
