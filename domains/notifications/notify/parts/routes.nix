# domains/notifications/notify/parts/routes.nix
#
# Default routing rules — pure data. First rule wins.
#
# `topicRoutes` is the single producer for the known topic vocabulary and its
# destinations. Each row generates two rules:
#   - priority 1 → the domain channel(s) plus SMTP
#   - any other priority → the domain channel(s)
#
# This keeps a critical alert in the channel that owns the topic while retaining
# the independent email path. A later generic P1 rule handles unknown critical
# topics. Unknown non-P1 topics fall through to defaultChannels (#ops), leaving
# matchedRule=null in the audit log so routing drift remains measurable.

let
  topicRoutes = [
    { topic = "automation";           channels = [ "discord-ops" ]; }
    # Historical hwc-crm-build emitters used `builds`; current gauntlets use
    # `nightly-builds`. Both are the same operator action domain.
    { topic = "builds";               channels = [ "discord-nightly-builds" ]; }
    { topic = "containers";           channels = [ "discord-ops" ]; }
    { topic = "events";               channels = [ "discord-events" ]; }
    { topic = "finance";              channels = [ "discord-finance" ]; }
    { topic = "frigate";              channels = [ "discord-frigate" ]; }
    { topic = "home-scout";           channels = [ "discord-home-scout" ]; }
    { topic = "immich";               channels = [ "discord-media" ]; }
    { topic = "jt-estimate";          channels = [ "discord-hwc-leads" ]; }
    { topic = "lead-scout";           channels = [ "discord-lead-scout" ]; }
    { topic = "media";                channels = [ "discord-media" ]; }
    { topic = "monitoring";           channels = [ "discord-ops" ]; }
    { topic = "nightly-builds";       channels = [ "discord-nightly-builds" ]; }
    { topic = "persona-daemon";       channels = [ "discord-ops" ]; }
    # Keep email as the complete long-form copy; Discord truncates embeds at
    # 4096 characters. The dedicated channel adds a scan-friendly scout view.
    { topic = "research-scout";       channels = [ "discord-research-scout" "smtp-office" ]; }
    { topic = "research-suggestions"; channels = [ "discord-research-scout" "smtp-office" ]; }
    { topic = "service";              channels = [ "discord-ops" ]; }
    { topic = "system";               channels = [ "discord-ops" ]; }
    { topic = "voice-log";            channels = [ "discord-ops" ]; }
    { topic = "website";              channels = [ "discord-website" ]; }
  ];

  withCriticalEmail = channels:
    if builtins.elem "smtp-office" channels
    then channels
    else channels ++ [ "smtp-office" ];

  criticalRule = route: {
    name = "${route.topic}-p1-to-domain-and-email";
    match = { inherit (route) topic; priority = 1; };
    channels = withCriticalEmail route.channels;
  };

  topicRule = route: {
    name = "${route.topic}-to-domain";
    match = { inherit (route) topic; };
    inherit (route) channels;
  };
in
[
  # Business leads stay isolated even when marked P1. This preserves the
  # deliberate boundary that prevents operations incidents from paging the
  # channel whose silence is itself a business signal.
  {
    name = "calculator-source-to-leads";
    match = { source = "calculator"; };
    channels = [ "discord-hwc-leads" ];
  }
  {
    name = "leads-topic-to-leads";
    match = { topic = "leads"; };
    channels = [ "discord-hwc-leads" ];
  }

  # Canary deliberately exercises Discord and SMTP together. Its timer remains
  # disabled until an independent off-host watcher exists.
  {
    name = "delivery-canary";
    match = { topic = "canary"; };
    channels = [ "discord-canary" "smtp-office" ];
  }
]
++ map criticalRule topicRoutes
++ [
  # A new P1 topic must still page even before its owner registers it below.
  {
    name = "unregistered-p1-to-ops-and-email";
    match = { priority = 1; };
    channels = [ "discord-ops" "smtp-office" ];
  }
]
++ map topicRule topicRoutes
