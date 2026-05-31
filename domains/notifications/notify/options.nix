# domains/notifications/notify/options.nix
#
# Schema for hwc.notifications.notify.*
#
# Phase 0: just the enable toggle. Phase 1 will flesh out port, secrets
# paths, route/channel data, audit-log retention, etc.

{ lib, ... }:

{
  options.hwc.notifications.notify = {
    enable = lib.mkEnableOption ''
      Hexagonal notification dispatcher (hwc-notify).
      Routes Notifications to Discord + SMTP; replaces the n8n alert-manager
      workflow and the per-script CLI senders. Implementation lands in
      Phase 1 — see ~/.claude/plans/hashed-snacking-crab.md.
    '';
  };
}
