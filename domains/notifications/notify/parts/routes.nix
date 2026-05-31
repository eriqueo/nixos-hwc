# domains/notifications/notify/parts/routes.nix
#
# Default routing rules — pure data. First-rule-wins; if no rule matches
# a notification, the dispatcher falls back to defaultChannels (see
# hwc.notifications.notify.defaultChannels).
#
# Each rule:
#   { name     — label shown in logs / dispatch response
#     match    — { topic? source? priority? }  (every set field is an
#                exact-match; empty {} = catchall)
#     channels — list of channel ids declared in parts/channels.nix
#   }
#
# Phase 1.3 keeps the matcher to exact equality on three fields. Regex,
# tags-any, priority-at-most can land in a later chunk when a routing
# case demands them.

[
  {
    name     = "leads-source-to-leads-channel";
    match    = { source = "calculator"; };
    channels = [ "discord-hwc-leads" ];
  }

  {
    name     = "lead-topic-to-leads-channel";
    match    = { topic = "leads"; };
    channels = [ "discord-hwc-leads" ];
  }

  {
    name     = "p1-fanout";
    # Critical alerts go everywhere — leads channel doubles as a "phone
    # might actually buzz" surface for late-night pages.
    match    = { priority = 1; };
    channels = [ "discord-hwc-alerts" "discord-hwc-leads" ];
  }

  {
    name     = "monitoring-to-alerts";
    match    = { topic = "monitoring"; };
    channels = [ "discord-hwc-alerts" ];
  }
]
