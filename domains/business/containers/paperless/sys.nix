{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.business.paperless;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tesseract
      poppler-utils
    ];
  };
}
