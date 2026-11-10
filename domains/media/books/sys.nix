{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.books;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/books/config";
  runtime = let value = builtins.fromJSON config.system.build.booksRuntimeBinding.text;
    in assert value.schemaVersion == 1; value;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "books";
      image = cfg.image;
      pull = if lib.hasPrefix "localhost/books-runtime:" cfg.image then "never" else "missing";
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:5299" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
        "${config.hwc.paths.media.root}/books:/books"
      ];
      # Calibre and its native dependencies are baked into the selected image.
      environment = lib.optionalAttrs (cfg.image == runtime.image) runtime.environment;
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
    })
  ]);
}
