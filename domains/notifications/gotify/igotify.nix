# domains/notifications/gotify/igotify.nix
#
# iGotify Notification Assistant — bridges Gotify to Apple Push Notifications
#
# Without this, the iGotify iOS app can only show notifications when opened.
# This container maintains a WebSocket connection to Gotify and relays
# messages through SecNtfy to Apple APNs for real push notifications.
#
# NAMESPACE: hwc.notifications.gotify.igotify.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.gotify.igotify;
  gotifyCfg = config.hwc.notifications.gotify;
in
{
  options.hwc.notifications.gotify.igotify = {
    enable = lib.mkEnableOption "iGotify Notification Assistant for iOS push notifications";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/androidseb25/igotify-notification-assist:latest";
      description = "iGotify Notification Assistant container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8681;
      description = "Host port for iGotify Assistant API";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc/igotify-assistant";
      description = "Data directory for iGotify Assistant";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.igotify-assistant = {
      image = cfg.image;
      autoStart = true;

      # Uses host networking to reach Gotify on 127.0.0.1
      extraOptions = [
        "--network=host"
        "--memory=128m"
        "--cpus=0.25"
      ];

      volumes = [
        "${cfg.dataDir}:/app/data"
      ];

      environment = {
        TZ = "America/Denver";
        ASPNETCORE_URLS = "http://+:${toString cfg.port}";
        GOTIFY_URLS = "http://127.0.0.1:${toString gotifyCfg.internalPort}";
        GOTIFY_CLIENT_TOKENS = "CfCyuyfY-eyxCZa";
        SECNTFY_TOKENS = "NTFY-DEVICE-Ek5h24QTerXKBpNX1AdfHpsn1sVcoC1V5XIcklt0ePNDg2nBUr3ahcI";
        ENABLE_CONSOLE_LOG = "true";
        ENABLE_SCALAR_UI = "false";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    assertions = [
      {
        assertion = !cfg.enable || gotifyCfg.enable;
        message = "iGotify Assistant requires the Gotify server (hwc.notifications.gotify.enable = true)";
      }
    ];
  };
}
