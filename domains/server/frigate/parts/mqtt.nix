# domains/server/frigate/parts/mqtt.nix
#
# Mosquitto MQTT Broker for Frigate
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;
in
{
  config = lib.mkIf (cfg.enable && cfg.mqtt.enable) {
    environment.systemPackages = with pkgs; [ mosquitto ];

    services.mosquitto = {
      enable = true;
      listeners = [{
        address = cfg.mqtt.host;
        port = cfg.mqtt.port;
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }];
    };
  };
}
