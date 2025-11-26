{ lib, config, pkgs, ... }:

let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.services.containers.books;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "books";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:5299:5299" ];
      volumes = [
        "/opt/downloads/books:/config"
        "${config.hwc.paths.hot}/downloads:/downloads"
        "${config.hwc.paths.media}/books:/books"
      ];
      environment = {
        # Optional: Enable Calibre integration for ebook management
        DOCKER_MODS = "linuxserver/mods:universal-calibre";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
    })
  ]);
}
