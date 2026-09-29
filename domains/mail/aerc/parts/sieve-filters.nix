# domains/mail/aerc/parts/sieve-filters.nix
#
# The Proton Sieve filters, generated from the mail taxonomy. Proton keeps
# only what must happen server-side, before mail reaches the phone or Laya:
#   01-junk     hard junk → Trash (taxonomy senders.trash, proton scope)
#   02-routing  preserves reviewed recipient/sender labels, Seen and Archive
#               actions from the eight live filters, mapped to existing targets.
# Interim routing retires in S4 when reviewed Laya rules and @-labels replace it.
# No rule stars mail.
#
# Proton Sieve notes (proton.me/support/sieve-advanced-custom-filters):
#   fileinto a folder moves; fileinto a label adds it; missing targets are skipped.
#   `stop` ends all subsequent filters; order 01-junk first.
{ lib }:
let
  t = (import ../../taxonomy/lib.nix { inherit lib; }).derived.protonTrash;

  q = s: ''"${lib.escape [ "\\" "\"" ] s}"'';
  list = xs: "[${lib.concatMapStringsSep ", " q xs}]";

  # A domain entry covers the domain and its subdomains.
  trashTests = lib.optionals (t.domains != []) [
      ''address :domain :is "from" ${list t.domains}''
      ''address :domain :matches "from" ${list (map (d: "*.${d}") t.domains)}''
    ]
    ++ lib.optional (t.addresses != []) ''address :all :is "from" ${list t.addresses}''
    ++ lib.optional (t.lists != []) ''header :is "x-pm-list-identifier" ${list t.lists}'';

  address = part: match: fields: values:
    ''address :${part} :${match} ${list fields} ${list values}'';
  from = values: address "all" "is" [ "From" ] values;
  to = values: address "all" "is" [ "To" "Cc" "Bcc" ] values;
  lists = values: ''header :is "x-pm-list-identifier" ${list values}'';
  any = tests: "anyof (${lib.concatStringsSep ", " tests})";
  all = tests: "allof (${lib.concatStringsSep ", " tests})";

  # Temporary by design: retire this data list with the old labels in S4,
  # after @-label sync and reviewed Laya routing rules preserve these actions.
  routingRules = [
    { test = to [ "eric@iheartwoodcraft.com" ]; labels = [ "work" ]; }
    { test = to [ "eriqueo@proton.me" "eriqueokeefe@gmail.com" ]; labels = [ "personal" ]; }
    { test = to [ "admin@iheartwoodcraft.com" ]; labels = [ "admin" ]; }
    { test = to [ "office@iheartwoodcraft.com" ]; labels = [ "office" ]; }
    { test = address "domain" "is" [ "To" "Cc" "Bcc" ] [ "contractorcto.com" ]; labels = [ "datax" ]; }
    { test = to [ "eric@contractorcto.com" ]; labels = [ "CTO" ]; }
    { test = from [ "kyle@remodelersontherise.com" "info@hammerandgrind.com"
        "tom@thecontractorfight.com" "info@contractorgrowthnetwork.com" "hi@xotara.us"
        "tony.fraserjones@profitabletradie.com" "phil.smith@profitabletradie.com" ];
      labels = [ "coaching" ]; }
    { test = lists [ "@support=theadhdtools.com@f.kajabimail.net"
        "@phil.smith@profitabletradie.com" "@tony.fraserjones@profitabletradie.com"
        "@chuck=adaptdigitalsolutions.com@no-reply.adaptdigitalsolutions.com"
        "@tom@thecontractorfight.com" "@info=hammerandgrind.com@mg.hammercrm.com"
        "@jobcosting@c.kajabimail.net" "@certification@narihq.org"
        "@spokane@scorevolunteer.org" ]; labels = [ "coaching" ]; spamGuard = false; }
    { test = from [ "hello@classdojo.com" "parent@classdojo.com" ]; labels = [ "family" ]; }
    { test = lists [ "@hello@classdojo.com" "@parent@classdojo.com" ];
      labels = [ "family" ]; spamGuard = false; }
    { test = lists [ "@team@news-mail.elementor.com" "@team@user-mail.elementor.com"
        "general.ollama.com@hello@ollama.com" "@rafal@supadata.ai"
        "@no-reply@news.termius.com" "@b2b@marketing.lenovo.com"
        "@noreply@email.openai.com" "@billing@limitloginattempts.com"
        "@support@limitloginattempts.com" ]; labels = [ "tech" ]; spamGuard = false; }
    { test = any [ (from [ "noreply@github.com"
        "invoice+statements+acct_1q84at2lwdzlekqf@stripe.com" ])
        (address "all" "contains" [ "From" ] [ "semrush.com" ]) ]; labels = [ "tech" ]; }
    { test = any [ (from [ "notifications@github.com" "noreply@status.io" ])
        ''header :contains "Subject" "Your Weekly WP Mail SMTP Summary for iheartwoodcraft.com"'' ];
      labels = [ "tech" ]; seen = true; }
    { test = lists [ "@business-noreply@mail.instagram.com"
        "@advertise-noreply@support.facebook.com" "@noreply@developers.facebook.com"
        "@notification@facebookmail.com" "@noreply@business.facebook.com" ];
      labels = [ "ads" ]; spamGuard = false; }
    { test = from [ "ads-account-noreply@google.com" "ads-noreply@google.com" ]; labels = [ "ads" ]; }
    { test = lists [ "@dnolan@mc-ws.com" "@ndray@mc-ws.com" "@nicole.dray@farther.com"
        "@No_Reply@notifications.intuit.com" ]; labels = [ "finance" ]; spamGuard = false; }
    { test = from [ "no_reply@email.apple.com" "alerts@notify.wellsfargo.com"
        "pncbank_statements@pnc.com" "no_reply@notifications.intuit.com" ]; labels = [ "finance" ]; }
    { test = address "domain" "matches" [ "From" ] [ "bankofamerica.com" "*.bankofamerica.com" ];
      labels = [ "finance" "bank" ]; }
    { test = address "domain" "matches" [ "From" ] [ "statefarm.com" "*.statefarm.com"
        "statefarmservice.com" "*.statefarmservice.com" ]; labels = [ "insurance" "finance" ]; }
    { test = from [ "hello@mercury.com" ]; labels = [ "bank" ]; }
    { test = from [ "office@kenyonnoble.com" "bailey@remodelersontherise.com" ]; labels = [ "work" ]; }
    { test = lists [ "@noreply@mxtoolbox.com" "@no-reply@email.claude.com"
        "@noreply@business-updates.facebook.com" "@dist.admin1013@scorevolunteer.org" ];
      seen = true; spamGuard = false; }
    { test = from [ "no-reply@accounts.google.com" ]; seen = true; }
    { test = lists [ "@vimeo@vimeo.com" ]; archive = true; seen = true; spamGuard = false; }
    { test = from [ "thecodinggopher@substack.com" ]; labels = [ "tech" ]; archive = true; seen = true; }
    { test = any [ (address "all" "contains" [ "From" ] [ "builds@sr.ht" "aerc" ])
        (address "all" "contains" [ "To" "Cc" "Bcc" ]
          [ "~rjarry/aerc-devel@lists.sr.ht" "~rjarry/aerc-discuss@lists.sr.ht" ]) ];
      labels = [ "aerc" "tech" ]; archive = true; seen = true; }
    { test = address "all" "contains" [ "From" ] [ "dmarc" ];
      labels = [ "website" "tech" ]; archive = true; seen = true; }
    { test = all [ ''header :contains "Subject" "New demo request →"''
        (from [ "support@comms.datax.to" ]) (to [ "hello@contractorcto.com" ]) ];
      labels = [ "datax" ]; archive = true; seen = true; }
  ];
  spamTest = ''allof (environment :matches "vnd.proton.spam-threshold" "*", spamtest :value "ge" :comparator "i;ascii-numeric" "''${1}")'';
  routingRule = r: ''
    if ${if r.spamGuard or true then all [ "not ${spamTest}" r.test ] else r.test} {
        ${lib.optionalString (r.seen or false) ''addflag "\\Seen";''}
        ${lib.optionalString (r.archive or false) ''fileinto "Archive";''}
        ${lib.concatMapStringsSep "\n        " (label: "fileinto ${q label};") (r.labels or [])}
    }'';
  n = xs: toString (builtins.length xs);
  header = name: ''
    # Proton filter "${name}" — generated by nixos-hwc
    # domains/mail/aerc/parts/sieve-filters.nix. Do not edit in Proton; paste over it.
    require ["fileinto", "imap4flags"];
  '';
in
{
  # Changes whenever senders.trash changes. Must be ordered first in Proton.
  "01-junk.sieve" = ''
    ${header "01 - Junk"}
    # Hard junk → Trash (${n t.domains} domains, ${n t.addresses} addresses, ${n t.lists} newsletter lists)
    # Source of truth: domains/mail/taxonomy/data.nix (senders.trash).
    if anyof (
        ${lib.concatStringsSep ",\n        " trashTests}
    ) {
        addflag "\\Seen";
        fileinto "Trash";
        stop;
    }
  '';

  # Interim non-trash actions retire in S4. No Flagged or nonexistent targets.
  "02-routing.sieve" = ''
    # Proton filter "02 - Routing" — generated by nixos-hwc
    # Interim live-rule actions; removal condition: S4 label consolidation.
    require ["fileinto", "imap4flags", "environment", "variables", "relational", "comparator-i;ascii-numeric", "spamtest"];
    ${lib.concatMapStringsSep "\n" routingRule routingRules}

    # Hide-my-email alias → the one existing custom folder.
    if address :all :is ["To", "Cc", "Bcc"] "camelcity.derail128@passmail.com" {
        fileinto "hide_my_email";
        stop;
    }
  '';
}
