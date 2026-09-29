{ config, lib, pkgs, inputs, osConfig ? {}, ... }:
let
  cfg = config.hwc.mail.classifier;
  account = config.hwc.mail.accounts.proton;
  common = import ../accounts/helpers.nix { inherit lib; };
  syncStatus = config.hwc.mail.mbsync.statusFile;
  command = pkgs.writeShellApplication {
    name = "mail-classifier";
    runtimeInputs = [ pkgs.notmuch pkgs.pass ];
    text = ''
      runtime=/run/current-system/sw/bin/mail-classifier-runtime
      if [ ! -x "$runtime" ]; then
        echo "mail-classifier-runtime is not active on this host" >&2
        exit 69
      fi
      case "''${1:-}" in
        ${lib.optionalString cfg.residency.enable ''
        observe-residency|label-probe)
          verb="$1"
          shift
          guard=()
          transport_args=(--notmuch ${pkgs.notmuch}/bin/notmuch)
          output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/residency-shadow.json"}
          if [ "$verb" = label-probe ]; then
            guard=(${pkgs.util-linux}/bin/flock -n -E 75 ${lib.escapeShellArg "${builtins.dirOf syncStatus}/sync.lock"})
            transport_args=()
            output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/label-probe.json"}
          fi
          exec "''${guard[@]}" "$runtime" "$verb" \
            --db /var/lib/hwc/mail-classifier/ledger.sqlite \
            --output "$output" \
            --bridge-host ${lib.escapeShellArg (common.getOr account "imapHost" (common.imapHost account))} \
            --bridge-port ${toString (common.getOr account "imapPort" (common.imapPort account))} \
            --bridge-login ${lib.escapeShellArg (common.loginOf account)} \
            --password-command ${lib.escapeShellArg (common.passCmd account)} "''${transport_args[@]}" "$@"
          ;;
        ''}
        correct|transition|reopen|review|route-review)
          verb="$1"
          shift
          exec "$runtime" "$verb" \
            --db /var/lib/hwc/mail-classifier/ledger.sqlite \
            --notmuch ${pkgs.notmuch}/bin/notmuch "$@"
          ;;
        route-manage|route-list|route-set|route-disable)
          verb="$1"
          shift
          exec "$runtime" "$verb" \
            --db /var/lib/hwc/mail-classifier/ledger.sqlite "$@"
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
  options.hwc.mail.classifier.contract = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = builtins.fromJSON (builtins.readFile "${inputs.system-one}/scripts/mail_classifier_contract.json");
    description = "The shared System One mail vocabulary used by every transport consumer";
  };
  options.hwc.mail.classifier.residency = {
    enable = lib.mkEnableOption "read-only Proton residency shadow after successful core sync" // {
      default = lib.attrByPath [ "hwc" "mail" "classifier" "system" "enable" ] false osConfig
        && config.hwc.mail.bridge.enable && cfg.enable;
    };
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${command}/bin/mail-classifier observe-residency";
      description = "Derived command for the sync owner; has no mail-write mode";
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf (config.hwc.mail.enable && cfg.enable) {
    home.packages = [ command ];
  };
}
