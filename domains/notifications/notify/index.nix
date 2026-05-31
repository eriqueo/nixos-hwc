# domains/notifications/notify/index.nix
#
# hwc-notify — hexagonal notification dispatcher.
#
# Replaces the n8n alert-manager workflow and the per-script CLIs
# (hwc-gotify-send, hwc-webhook-send, hwc-smartd-notify, …) with one
# TypeScript service exposing HTTP + CLI + MCP shells and pluggable
# outbound adapters (Discord, SMTP, …).
#
# NAMESPACE: hwc.notifications.notify.*
#
# STATUS: Phase 0 scaffold only — module evaluates clean when disabled
# but enabling it asserts until the Phase 1 implementation lands.
#
# See ~/.claude/plans/hashed-snacking-crab.md for the design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.notify;
in
{
  # OPTIONS
  imports = [ ./options.nix ];

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    # Phase 1 will:
    #   - bundle src/ into the Nix store via lib.sources.sourceFilesBySuffices
    #   - declare systemd.services.hwc-notify (User=eric, hardening, env from
    #     module options + agenix paths)
    #   - install a `hwc-notify` CLI shim that talks to the local HTTP shell
    #   - export channels/routes JSON for the service to load at startup
    # Until then, enabling this module is an error so callers can't depend
    # on a non-existent service.
    assertions = [
      {
        assertion = false;
        message = ''
          hwc.notifications.notify is scaffolded but not yet implemented.
          See ~/.claude/plans/hashed-snacking-crab.md Phase 1 for the design.
        '';
      }
    ];
  };
}
