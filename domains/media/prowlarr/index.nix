{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.prowlarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.apps.root}/prowlarr/config";
  arrConfig = import ../arr-config.nix { inherit lib pkgs; };
  enforceScript = arrConfig.mkArrConfigScript {
    name = "prowlarr";
    port = (import ../../networking/ports.nix).prowlarr.port;
    inherit configPath;
    urlBase = "";  # vhost at prowlarr.<vhostDomain>; no path prefix
  };
in
{
  options.hwc.media.prowlarr = {
    enable = lib.mkEnableOption "prowlarr container";
    port = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).prowlarr.port; };
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/prowlarr:latest"; description = "Container image"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "prowlarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:${toString (import ../../networking/ports.nix).prowlarr.port}" ];
      volumes = [ "${configPath}:/config" ];
      environment = {
        # Empty = served at root; prowlarr.hwc.iheartwoodcraft.com is a vhost.
        PROWLARR__URLBASE = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    {
    # Service dependencies
    systemd.services."podman-prowlarr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-prowlarr".wants = [ "network-online.target" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-prowlarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  }
  ]);
}
