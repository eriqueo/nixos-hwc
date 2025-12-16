# slskd configuration file generator (config-only - container moved to sys.nix)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.slskd;

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
  };
}
