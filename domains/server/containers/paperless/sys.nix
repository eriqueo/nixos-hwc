{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.paperless;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tesseract
      poppler_utils
    ];
  };
}
