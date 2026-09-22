# domains/mail/taxonomy/data.nix
#
# Reviewed sender dispositions, legacy/manual tag vocabulary, and action subjects.
# Workflow State, Domain, and model traits live in System One's pinned contract.
#
# PURE DATA: no options, no config, no pkgs. Imported at BUILD TIME from both
# lanes, so drift between consumers is structurally impossible:
#   HM lane     — notmuch rule defaults (notmuch/index.nix), aerc tags/colors
#                 (aerc/parts/tags.nix)
# See docs/plans/unified-triage-architecture.md and ./README.md.
#
# DISPOSITION SEMANTICS (behavior-preserving — premortem risk 2):
#   trash — legacy deny list for the separate Gmail janitor only. Local mail is
#           classified solely by Laya plus human ledger corrections.
{
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
      # user-confirmed recurring promos; exact senders preserve adjacent mail
      "Intuit@mkt.intuit.com"
      "nm_bozemandailychronicle@newsmemory.com"
      # marketing drip / cold social
      "linkedin.com" "nextdoor.com" "semrush.com" "jonloomer.com"
      "trainsemail.com" "thinkr.org" "constructionconsulting.co"
      "contractorcto.com" "nextlevelsystems.co" "qemailserver.com"
      "ccsend.com"
    ];

  };
}
