# slskd Soulseek daemon container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.slskd;
  mediaNetworkName = "media-network";
  hotRoot = "/mnt/hot";

  # Script to generate slskd config from secrets at runtime
  generateConfigScript = pkgs.writeShellScript "generate-slskd-config" ''
    WEB_USERNAME=$(cat ${config.age.secrets.slskd-web-username.path})
    WEB_PASSWORD=$(cat ${config.age.secrets.slskd-web-password.path})
    SOULSEEK_USERNAME=$(cat ${config.age.secrets.slskd-soulseek-username.path})
    SOULSEEK_PASSWORD=$(cat ${config.age.secrets.slskd-soulseek-password.path})
    API_KEY=$(cat ${config.age.secrets.slskd-api-key.path})

    cat > /etc/slskd/slskd.yml <<EOF
debug: false
headless: false
remote_configuration: false
remote_file_management: false
web:
  port: 5030
  https:
    disabled: true
    port: 5031
    force: false
  authentication:
    disabled: false
    username: $WEB_USERNAME
    password: $WEB_PASSWORD
    jwt:
      key: "Nd5g9X1AcVck7z7Q4Yq0IuULeQ7ci/Zu7++Lmcq7jOqF0e6ZbCvp5SmWVBN3EAVE"
      ttl: 604800000
    api_keys:
      soularr:
        key: $API_KEY
        role: readwrite
        cidr: 0.0.0.0/0,::/0
directories:
  downloads: /downloads/music
  incomplete: /downloads/incomplete
shares:
  directories:
    - "[Downloads]/downloads/music"
    - "[Library]/music"
soulseek:
  username: $SOULSEEK_USERNAME
  password: $SOULSEEK_PASSWORD
  description: "A slskd user. https://github.com/slskd/slskd"
  listen_ip_address: "0.0.0.0"
  listen_port: 50300
EOF
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Directory creation handled by container-directories-setup.service (_shared/directories.nix)
    # No tmpfiles rules needed - eliminates duplicates and unsafe path transitions

    # Systemd service to generate config from secrets before container starts
    systemd.services.slskd-config-generator = {
      description = "Generate slskd configuration from agenix secrets";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-slskd.service" ];
      after = [ "agenix.service" "container-directories-setup.service" ];
      requires = [ "container-directories-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${generateConfigScript}";
      };
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
    systemd.services."podman-slskd".after = [ "network-online.target" "init-media-network.service" "slskd-config-generator.service" "mnt-hot.mount" ];
    systemd.services."podman-slskd".wants = [ "network-online.target" ];
    systemd.services."podman-slskd".requires = [ "slskd-config-generator.service" "mnt-hot.mount" ];
  };
}
