{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "jellyseerr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:5055:5055" ];
      volumes = [
        "/opt/jellyseerr/config:/app/config"
      ];
      environment = {
        # No URL_BASE needed in port mode
      };
      dependsOn = [ "sonarr" "radarr" ];
    })

    # Ensure persistent storage directory exists with correct permissions
    {
      systemd.tmpfiles.rules = [
        "d /opt/jellyseerr/config 0755 568 568 -"
        # Pre-configure Jellyfin connection settings
        ''f+ /opt/jellyseerr/config/settings.json 0644 568 568 - ${pkgs.writeText "jellyseerr-settings.json" (builtins.toJSON {
          jellyfin = {
            name = "Jellyfin";
            ip = "10.89.0.1";  # Gateway IP (host from container perspective)
            port = 8096;
            useSsl = false;
            urlBase = "";
            externalHostname = "";
            jellyfinForgotPasswordUrl = "";
            libraries = [];
            serverId = "";
            apiKey = "";
          };
          main = {
            mediaServerType = 4;  # Jellyfin
          };
        })}''
      ];
    }
  ]);
}
