{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.business.paperless;
  emailToPaperlessPython = pkgs.python3.withPackages (ps: [ ps.reportlab ]);
  emailToPaperless = pkgs.writeShellScriptBin "email-to-paperless" ''
    exec ${emailToPaperlessPython}/bin/python3 \
      ${./scripts/email-to-paperless.py} \
      --consume-dir ${lib.escapeShellArg (toString cfg.storage.consumeDir)} \
      --staging-dir ${lib.escapeShellArg (toString cfg.storage.stagingDir)} \
      "$@"
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tesseract
      poppler-utils
    ] ++ [ emailToPaperless ];
  };
}
