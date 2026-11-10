{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.radarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.apps.root}/radarr/config";
  arrConfig = import ../arr-config.nix { inherit lib pkgs; };
  enforceScript = arrConfig.mkArrConfigScript {
    name = "radarr";
    port = (import ../../networking/ports.nix).radarr.port;
    inherit configPath;
    urlBase = "";  # vhost at radarr.<vhostDomain>; no path prefix
  };
  webhookScript = arrConfig.mkArrWebhookScript {
    name = "radarr";
    inherit configPath;
    source = "radarr";
    webhookUrl = "${config.hwc.automation.n8n.publicUrl}/webhook/media-pipeline";
  };
in
{
  options.hwc.media.radarr = {
    enable = lib.mkEnableOption "radarr container";
    port = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).radarr.port; };
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/radarr:latest"; description = "Container image"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "radarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:${toString (import ../../networking/ports.nix).radarr.port}" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.media.root}/movies:/movies"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        # Empty = served at root; radarr.hwc.iheartwoodcraft.com is a vhost.
        RADARR__URLBASE = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
    {
    # Service dependencies
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-radarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings and webhook before container starts
    systemd.services."podman-radarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"   # + prefix runs as root
      "+${webhookScript}"
    ];
  }
  ]);
}
