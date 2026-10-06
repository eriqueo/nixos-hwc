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
        observe-residency|observe-phone-labels|label-probe|project-labels|review-label-write|transport)
          verb="$1"
          shift
          guard=()
          transport_args=(--notmuch ${pkgs.notmuch}/bin/notmuch)
          output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/residency-shadow.json"}
          output_args=()
          if [ "$verb" = label-probe ]; then
            transport_args=()
            output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/label-probe.json"}
          fi
          if [ "$verb" = review-label-write ]; then
            output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/label-review.json"}
          fi
          if [ "$verb" = observe-phone-labels ]; then
            output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/phone-label-shadow.json"}
          fi
          if [ "$verb" = project-labels ]; then
            output=${lib.escapeShellArg "${builtins.dirOf syncStatus}/labels.json"}
          fi
          if [ "$verb" != transport ]; then
            output_args=(--output "$output")
          fi
          if [ "$verb" != observe-residency ] && [ "''${SYNC_MAIL_LOCKED:-0}" != 1 ]; then
            guard=(${pkgs.util-linux}/bin/flock -n -E 75 ${lib.escapeShellArg "${builtins.dirOf syncStatus}/sync.lock"})
          fi
          exec "''${guard[@]}" "$runtime" "$verb" \
            --db /var/lib/hwc/mail-classifier/ledger.sqlite \
            "''${output_args[@]}" \
            --bridge-host ${lib.escapeShellArg (common.getOr account "imapHost" (common.imapHost account))} \
            --bridge-port ${toString (common.getOr account "imapPort" (common.imapPort account))} \
            --bridge-login ${lib.escapeShellArg (common.loginOf account)} \
            --password-command ${lib.escapeShellArg (common.passCmd account)} "''${transport_args[@]}" "$@"
          ;;
        ''}
        correct|transition|reopen|review|route-review|migrate-uncertainty)
          verb="$1"
          shift
          guard=()
          if [ "$verb" != review ] && [ "''${SYNC_MAIL_LOCKED:-0}" != 1 ]; then
            guard=(${pkgs.util-linux}/bin/flock -n -E 75 ${lib.escapeShellArg "${builtins.dirOf syncStatus}/sync.lock"})
          fi
          exec "''${guard[@]}" "$runtime" "$verb" \
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
  options.hwc.mail.classifier.projection = {
    enable = lib.mkEnableOption "bounded one-way Proton label projection after healthy core sync" // {
      default = cfg.residency.enable;
    };
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${command}/bin/mail-classifier project-labels --apply";
      description = "Shared writer for managed labels; never teaches or changes real folders";
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf (config.hwc.mail.enable && cfg.enable) {
    home.packages = [ command ];
    assertions = [{
      assertion = !cfg.projection.enable || (cfg.residency.enable && cfg.contract.protonSync ? projection);
      message = "Proton label projection requires healthy residency prerequisites";
    }];
  };
}
