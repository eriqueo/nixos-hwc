# domains/mail/taxonomy/data.nix
#
# Canonical mail taxonomy — THE single source of truth for tag vocabulary,
# triage buckets, sender dispositions, and action subjects.
#
# PURE DATA: no options, no config, no pkgs. Imported at BUILD TIME from both
# lanes, so drift between consumers is structurally impossible:
#   HM lane     — notmuch rule defaults (notmuch/index.nix), aerc tags/colors
#                 (aerc/parts/tags.nix)
#   system lane — MCP gateway (mail-taxonomy.json via system/mcp/index.nix),
#                 morning-briefing triage prompt (business/morning-briefing)
# See docs/plans/unified-triage-architecture.md and ./README.md.
#
# DISPOSITION SEMANTICS (behavior-preserving — premortem risk 2):
#   trash        — auto-trashed on arrival by notmuch rules (never reaches inbox)
#   archive      — auto-archived on arrival (kept in All Mail, out of inbox)
#   newsletter   — +newsletter -inbox on arrival
#   notification — +notification -inbox on arrival
#   finance      — +finance -inbox on arrival
#   noise        — LLM-ADVISORY ONLY: the triage prompt buckets these as noise.
#                  NEVER fed to the auto-trash rules. Promoting a sender to
#                  trash is a deliberate per-sender move between lists.
#   review       — LLM-ADVISORY ONLY: the triage prompt buckets these as review.
# All rule-fed senders (trash/archive) are ALSO emitted into the prompt's
# noise list — the safe merge direction (see lib.nix promptFragment).
{
  # Triage buckets — tag-backed kanban placement (`triage/<bucket>` notmuch
  # tags). Shared by run.sh Step 2b, hwc_mail set-triage, hwc_mail_triage.
  triage = {
    buckets = [ "urgent" "review" "noise" ];
    tagPrefix = "triage/";
  };

  # Semantic groups → theme palette ROLE (not hex — theme is presentation,
  # not taxonomy; aerc maps role→hex from the active palette).
  groups = {
    business = "accent";        # copper-orange — HWC brand
    money    = "info";          # blue — cool/financial
    personal = "warningBright"; # bright amber — warm/personal
    growth   = "success";       # sage green — development
    system   = "fg3";           # muted gray — low noise
    urgent   = "error";         # red — demands attention
    waiting  = "warning";       # amber — needs follow-up
  };

  # Category tags — mutually exclusive (assigning one removes the others).
  # display = "tag_key" sidebar cue; spaceKey = aerc <Space>m leader key.
  categories = [
    # ── Business ──
    { tag = "office";       group = "business"; display = "office_o";       spaceKey = "o"; }
    { tag = "work";         group = "business"; display = "work_w";         spaceKey = "w"; }
    { tag = "hwcmt";        group = "business"; display = "hwcmt_h";        spaceKey = "h"; dim = true;
      query = "(to:heartwoodcraftmt@gmail.com OR from:heartwoodcraftmt@gmail.com) AND NOT tag:trash"; }

    # ── Money ──
    { tag = "finance";      group = "money";    display = "finance_f";      spaceKey = "f"; }
    { tag = "bank";         group = "money";    display = "bank_b";         spaceKey = "b"; }
    { tag = "insurance";    group = "money";    display = "insurance_$";    spaceKey = "$"; dim = true; }

    # ── Personal ──
    { tag = "personal";     group = "personal"; display = "personal_p";     spaceKey = "p"; }
    { tag = "family";       group = "personal"; display = "family_y";       spaceKey = "y"; }
    { tag = "eriqueokeefe"; group = "personal"; display = "eriqueokeefe_e"; spaceKey = "e";
      query = "(to:eriqueokeefe@gmail.com OR from:eriqueokeefe@gmail.com) AND NOT tag:trash"; }

    # ── Growth ──
    { tag = "admin";        group = "growth";   display = "admin_n";        spaceKey = "n"; }
    { tag = "coaching";     group = "growth";   display = "coaching_c";     spaceKey = "c"; }

    # ── System ──
    { tag = "tech";         group = "system";   display = "tech_t";         spaceKey = "t"; }
    { tag = "aerc";         group = "system";   display = "aerc_~";         spaceKey = "`"; }
    { tag = "website";      group = "system";   display = "website_@";      spaceKey = "@"; }
  ];

  # Flag tags — coexist with categories (not exclusive), not inbox-scoped.
  flags = [
    { tag = "action";  group = "urgent";  display = "action_!";  spaceKey = "!"; bold = true; }
    { tag = "pending"; group = "waiting"; display = "pending_?"; spaceKey = "?"; }
    # Protected family/friends correspondence (preserved from Gmail All Mail,
    # 2007+). Non-inbox-scoped so the folder shows the whole archive.
    # protected: bulk "clear all tags" operations must never strip this tag
    # (the keep-shield and the janitor's Family-Friends exclusion rely on it).
    { tag = "keep";    group = "growth";  display = "keep_k";    spaceKey = "k"; protected = true; }
  ];

  senders = {
    # Pure noise — auto-trashed on arrival (2026-06 Gmail backlog audit).
    trash = [
      # lead-gen platforms
      "angi.com" "angieslist.com" "homeadvisor.com" "wix.com"
      # marketing drip / cold social
      "linkedin.com" "nextdoor.com" "semrush.com" "jonloomer.com"
      "trainsemail.com" "thinkr.org" "constructionconsulting.co"
      "contractorcto.com" "nextlevelsystems.co" "qemailserver.com"
      "ccsend.com"
    ];

    # Low-value-but-keepable — auto-archived (out of inbox, kept in All Mail).
    archive = [
      # retail / suppliers (receipts tracked in QB/JobTread; keep findable)
      "amazon.com" "sherwin.com" "harborfreight.com" "homedepot.com"
      "bruntworkwear.com" "fergusonhome.com" "bestbuy.com" "soundcore.com"
      "jossandmain.com" "plumdragonherbs.com" "hibid.com"
      # coaching / industry
      "builttobuildacademy.com" "narihq.org" "agingcare.com"
      "thecontractorfight.com"
      # bulk / SaaS marketing
      "mailchimpapp.com" "zapier.com" "supadata.ai" "beehiiv.com"
      "sage.com" "perplexity.ai" "vimeo.com"
    ];

    # +newsletter -inbox on arrival (address patterns; rules.nix also matches
    # any list:"*" header).
    newsletter = [ "newsletter@" "news@" "updates@" "digest@" "list@" "mailer@" ];

    # +notification -inbox on arrival.
    notification = [ "no-reply@" "noreply@" "notifications@" "notices@" "github.com" ];

    # +finance -inbox on arrival.
    finance = [
      "amazon.com" "paypal.com" "stripe.com" "squareup.com" "intuit.com"
      "quickbooks" "chase.com" "bankofamerica.com"
    ];

    # LLM-advisory noise — reaches the inbox, but the triage prompt always
    # buckets it as noise (suggested_action: trash). Entries are strings or
    # { match, note }.
    noise = [
      "alignable.com"
      "profitabletradie.com"
      "theprofessionalbuilder.com"
      "bf10x.hubspotemail.net"
      "stantaylor.com"
      "mg.homedepot.com"
      "your.cvs.com"
      "emailinfo.bestbuy.com"
      "mail.instagram.com"
      "bniconnectglobal.com"
      { match = "quora.com"; note = "digest emails"; }
      { match = "zillow.com"; note = "marketing"; }
      { match = "thumbtack.com"; note = "notifications"; }
      { match = "yelp.com"; note = "business promotions"; }
      { match = "Any sender matching \"*estimat*\", \"*takeoff*\", \"*bid*\" @gmail.com"; note = "cold outreach pattern"; }
    ];

    # LLM-advisory review — legitimate platforms/newsletters worth a glance.
    review = [
      { match = "ollama"; note = "tech newsletter"; }
      { match = "Bozeman Area Chamber of Commerce"; note = "local business events"; }
      { match = "Google Local Services Ads (lsa.google.com, google.com notifications)"; note = "lead platform Eric actively uses"; }
      { match = "GitHub"; note = "unless CI failure from eriqueo/* repo → urgent"; }
      { match = "iCloud"; note = "system/security notifications"; }
      { match = "MxToolbox"; note = "deliverability summary"; }
      { match = "Quo/OpenPhone (quo.com, openphone.com)"; note = "business phone notifications"; }
      { match = "Stripe (stripe.com)"; note = "payment processing"; }
      { match = "QuickBooks (intuit.com)"; note = "accounting"; }
      { match = "JobTread (jobtread.com)"; note = "project management"; }
    ];
  };

  # Subjects that get +action on arrival (kept in inbox).
  actionSubjects = [
    "invoice" "quote" "proposal" "estimate" "RFP" "action required"
    "approve" "signature" "past due"
  ];
}
