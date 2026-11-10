{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.lidarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.apps.root}/lidarr/config";
  arrConfig = import ../arr-config.nix { inherit lib pkgs; };
  enforceScript = arrConfig.mkArrConfigScript {
    name = "lidarr";
    port = (import ../../networking/ports.nix).lidarr.port;
    inherit configPath;
    urlBase = "";  # vhost at lidarr.<vhostDomain>; no path prefix
  };
  webhookScript = arrConfig.mkArrWebhookScript {
    name = "lidarr";
    inherit configPath;
    source = "lidarr";
    webhookUrl = "${config.hwc.automation.n8n.publicUrl}/webhook/media-pipeline";
  };
in
{
  options.hwc.media.lidarr = {
    enable = lib.mkEnableOption "lidarr container";
    port = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).lidarr.port; };
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/lidarr:2.13.3";
      description = "Container image (pinned version - develop branch has NullRef bug in Distance.Clean())";
    };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "lidarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:${toString (import ../../networking/ports.nix).lidarr.port}" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.media.root}/music:/music"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        # Empty = served at root; lidarr.hwc.iheartwoodcraft.com is a vhost.
        LIDARR__URLBASE = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
    {
    # Service dependencies
    systemd.services."podman-lidarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-lidarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-lidarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings and webhook before container starts
    systemd.services."podman-lidarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"   # + prefix runs as root
      "+${webhookScript}"
    ];
  }
  ]);
}
