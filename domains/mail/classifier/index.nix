{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.mail.classifier;
  command = pkgs.writeShellApplication {
    name = "mail-classifier";
    runtimeInputs = [ pkgs.notmuch ];
    text = ''
      runtime=/run/current-system/sw/bin/mail-classifier-runtime
      if [ ! -x "$runtime" ]; then
        echo "mail-classifier-runtime is not active on this host" >&2
        exit 69
      fi
      case "''${1:-}" in
        correct|review)
          verb="$1"
          shift
          exec "$runtime" "$verb" \
            --db /var/lib/hwc/mail-classifier/ledger.sqlite \
            --notmuch ${pkgs.notmuch}/bin/notmuch "$@"
          ;;
        *) exec "$runtime" "$@" ;;
      esac
    '';
  };
in
{
  # OPTIONS
  options.hwc.mail.classifier.enable = lib.mkEnableOption "local Laya mail-classifier controls" // {
    default = true;
  };

  # IMPLEMENTATION
  config = lib.mkIf (config.hwc.mail.enable && cfg.enable) {
    home.packages = [ command ];
  };
}
