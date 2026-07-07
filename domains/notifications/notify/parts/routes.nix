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
    # Critical alerts go everywhere — both Discord channels for fast eyes
    # plus email so the alert survives Discord outages and ends up in the
    # mail archive for postmortems.
    match    = { priority = 1; };
    channels = [ "discord-hwc-alerts" "discord-hwc-leads" "smtp-office" ];
  }

  {
    name     = "monitoring-to-alerts";
    match    = { topic = "monitoring"; };
    channels = [ "discord-hwc-alerts" ];
  }

  {
    name     = "nightly-builds-to-builds-channel";
    match    = { topic = "nightly-builds"; };
    channels = [ "discord-nightly-builds" ];
  }

  # ── Explicit routes for the n8n workflows migrated off Slack ───────────
  # (jellyfin, voice-log, weekly/bozeman events, jt estimate). Each has a
  # named topic so it routes deliberately instead of falling through to
  # defaultChannels. All land on #hwc-alerts today — the only general
  # Discord channel — but the named topic makes re-homing a one-line edit
  # once per-domain channels exist. A priority=1 on any of these still hits
  # p1-fanout first (declared above), so criticals fan out to email too.

  {
    name     = "media-to-alerts";           # home:media:jellyfin-alert
    match    = { topic = "media"; };
    channels = [ "discord-hwc-alerts" ];
  }

  {
    name     = "voice-log-to-alerts";        # hwc:ops:voice-log
    match    = { topic = "voice-log"; };
    channels = [ "discord-hwc-alerts" ];
  }

  {
    name     = "events-to-alerts";           # home:social weekly + bozeman aggregator
    match    = { topic = "events"; };
    channels = [ "discord-hwc-alerts" ];
  }

  {
    name     = "jt-estimate-to-alerts";      # hwc:ops:jt:estimate-push
    match    = { topic = "jt-estimate"; };
    channels = [ "discord-hwc-alerts" ];
  }
]
