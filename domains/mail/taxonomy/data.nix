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
# DISPOSITION SEMANTICS:
#   trash — reviewed deny entries scoped to the Gmail janitor or Proton Sieve.
#           Local mail is classified by Laya plus human ledger corrections.
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

  # Historical category metadata retained for searches and folder styles.
  # These tags no longer generate assignment shortcuts or exclusive removal.
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
    # Pure noise. One list feeds both deterministic trash producers:
    #   gmail  — the Gmail janitor (matches domains; address entries are inert there)
    #   proton — the generated Proton Sieve script (aerc/parts/sieve-filters.nix)
    # Entry forms:
    #   "dom.com"                          domain + all subdomains, scope both
    #   "user@dom.com"                     exact From address, scope both
    #   { sender = "…"; scope = "gmail"; } restrict to one producer
    #   { list = "…"; }                    Proton x-pm-list-identifier (proton only):
    #                                      trashes a newsletter list without touching
    #                                      transactional mail from the same sender
    # No entry may match a protected domain (lib.nix throws).
    trash = [
      # lead-gen platforms
      "angi.com" "angieslist.com" "homeadvisor.com" "wix.com"
      # user-confirmed recurring promos; exact senders preserve adjacent mail
      "Intuit@mkt.intuit.com"
      "nm_bozemandailychronicle@newsmemory.com"
      # marketing drip / cold social
      "nextdoor.com" "jonloomer.com"
      "trainsemail.com" "thinkr.org" "constructionconsulting.co"
      "nextlevelsystems.co" "qemailserver.com"
      "ccsend.com"
      # Gmail-only: on Proton Laya judges it.
      { sender = "linkedin.com"; scope = "gmail"; }
    ] ++ builtins.map (sender: { inherit sender; scope = "proton"; }) [
      # ── 2026-04-05 inbox/archive audit (domains/mail/filter-audit-20260405.md) ──
      # marketing relays
      "send.mailerlite.eu" "mail.genierocket.com" "t.shopifyemail.com"
      # coaching drip
      "email.hammerandgrind.com" "seriousgrit.com"
      # networking spam
      "alignable.com" "bniconnectglobal.com"
      # product / SaaS marketing
      "shapr3d.com" "loox.io"
      # retail marketing subdomains
      "enews.united.com" "your.cvs.com" "insideapple.apple.com" "mg.homedepot.com"
      "mailing.hibid.com" "auctions.hibid.com" "service.hbomax.com" "mail.hbomax.com"
      "emailinfo.bestbuy.com" "e.acmetools.com" "service.jossandmain.com"
      # cold outreach
      "idealcostestimate.pro" "takeoffconsultants.net" "bestsoftwaredevelopmentcompany.com"
      "webappconsultant.com" "creativeweb.services" "mobwebify.com" "rankawe.com"
      "adcomt.com" "powerhousenow.com" "stantaylor.com" "harborinno.com"
      "shorefundingusa.net" "southerngulfcapital.com" "floridagulfcapital.com"
      # pure spam / junk
      "sedioliniauto.com" "treflio.com" "snorelessnow.com" "nupent.com"
      "marketsshelfs.com" "marblerenew.com" "hmmarblesink.com" "mails.zoloftlab.info"
      "mails.ukcz.info" "mails.postlight.info" "jarry.cc" "inv.alid.pw" "informatel.nl"
      "hsmgroup.directory" "heifetz.xyz" "go1001000.com" "flicket.io"
      "finanzkanzlei-adamietz.de" "bmyincplans.com" "nasilyan.com" "nasentc.com"
      "microkits.net" "econgobooks.com" "terrance.allofti.me" "sttlogisticsgroup.com"
      "ellasbubbles.com" "jimgreenfootwear.com" "powernailglobal.com"
      "fensterusa.com" "agesafeamerica.com" "mail.amrlocal.com" "hamradioprep.com"
      "mail.siriregistration.com"
      # mixed-use domains: exact marketing senders only
      "marketing@thumbtack.com" "do-not-reply@customer.thumbtack.com"
      "marketing@narihq.org" "info@narihq.org" "noreply@angi.com"
      "no-reply@offers.proton.me" "no-reply@news.proton.me" "business-updates@proton.me"
      # Gmail estimating / cold-outreach addresses (a snapshot; they rotate)
      "will.constructiontakeoffs@gmail.com" "wesley.biddingestimation@gmail.com"
      "tyler.primeestimation37@gmail.com" "tyler.speedyestimates@gmail.com"
      "aries.bidestimations@gmail.com" "theodore.titanestimates@gmail.com"
      "teddygeiger473@gmail.com" "valentinogonzalez531@gmail.com" "stimbidsaim76@gmail.com"
      "sandy.projectplansbreakdown@gmail.com" "russ.estimateandconstruct@gmail.com"
      "rowen.globalbids3367@gmail.com" "robert.precisescopeestimating@gmail.com"
      "reyes.estimategeneral@gmail.com" "paul.coreestimations@gmail.com"
      "olivia.estimanians2@gmail.com" "oben.swiftestimations@gmail.com"
      "noah.estimations3@gmail.com" "schaible.aimestimating@gmail.com"
      "matthew.primeestimation7@gmail.com" "markus.yoursestimates@gmail.com"
      "lucas.precisescopeestimations@gmail.com" "lisaphoenixestimation@gmail.com"
      "liam.parker.yoursestimatings@gmail.com" "liam.constructiontakeoff1155@gmail.com"
      "knox.constructionetakeoff19@gmail.com" "k.aimestimatings@gmail.com"
      "kari.makestimating@gmail.com" "julian.globalestimation@gmail.com"
      "joshue.aquaestimating@gmail.com" "joseph.constructionbidss@gmail.com"
      "john.aceccuracy.takeoff@gmail.com" "jason.usbasedprojects555@gmail.com"
      "jack.constructingestimates@gmail.com" "jack.contructionestimatesof@gmail.com"
      "jack.globalestimatings@gmail.com" "grant.aimestimate7@gmail.com"
      "gloria.perfectestimation@gmail.com" "fisher.aimestimating@gmail.com"
      "elijah.aimestimatestakeof@gmail.com" "edward.primeestimation45@gmail.com"
      "dominick.constructiontakeoff@gmail.com" "david.bidproestimation45@gmail.com"
      "daniel.estimation15@gmail.com" "daniel17estimationhubinc@gmail.com"
      "dan.30esthubinc@gmail.com" "chris.constructionbidding@gmail.com"
      "chrisjohn.takeoff@gmail.com" "cjohn.estimatings@gmail.com" "canon.estimates@gmail.com"
      "benjamincharlieestimation@gmail.com" "archieleo.yourstakeoff@gmail.com"
      "antonio.estimatingcraftllc@gmail.com" "anthony.superiorestimating.us@gmail.com"
      "andrewmasonglobelbids@gmail.com" "alan.speedybid@gmail.com"
      "adan.americanestimation7@gmail.com" "aimestimators.us@gmail.com"
      "561.estimation@gmail.com" "mike.construction.supervisor@gmail.com"
      "scott.constructions24@gmail.com" "rochelleswiftarchitecture@gmail.com"
      "lanarchitectservices@gmail.com" "johnn.swiftarchitecture@gmail.com"
      "ankita.webservice123@gmail.com"
      "shrek.ressurrected@gmail.com" "tymtomojaydon6743@gmail.com"
      "randi.fasttakeoff@gmail.com" "noah.globalestimates87@gmail.com"
      "greg.globalestimating@gmail.com" "emmett.civilstructialplanss190@gmail.com"
      "aaron.bidsandconstruction@gmail.com" "abttakeoff.chrisj@gmail.com"
      "charles.eliteworksconsulting@gmail.com" "mike.gracegroupllc4@gmail.com"
      "makerankseoservice@gmail.com" "secure.paypal.03@gmail.com" "levi.service56@gmail.com"

      # ── Eric's live Proton filter decisions (replacement pending review) ──
      # exact senders
      "newsletters@em.walmart.com" "feedback@reviews.walmart.com"
      "support_at_harborinno_com_jx68zp9cvx6e8g_9d7p7556@icloud.com"
      "YardHouse@e.yardhouse.com" "no-reply@stream.discoveryplus.com"
      "photo@mystore.cvs.com" "hello@board.fun" "Dell_Rewards@comms.dell.com"
      "shawncraft.com"
    ] ++ [
      # newsletter lists (Proton list-id; transactional mail from these senders is unaffected)
      { list = "@editor@members.wayfair.com"; }
      { list = "@TurboTax@em1.turbotax.intuit.com"; }
      { list = "@Mark@earlyaidopterscommunity.com"; }
      { list = "4a9aba8b8afd6c9889196a108.427577.list-id.mcsv.net@promotions@makitausa.com"; }
      { list = "@northmidwest@scorevolunteer.org"; }
      { list = "@notifications@account.brilliant.org"; }
      { list = "@no-reply@business.amazon.com"; }
      { list = "@contact@mail.replit.com"; }
      { list = "b3912e9c4104570679fdfcb94.436936.list-id.mcsv.net@methodestatemanagement@129441774.mailchimpapp.com"; }
      { list = "@team@mail.clickup.com"; }
      { list = "@no-reply@cncf.io"; }
      { list = "33346.direct_push@noreply@instapage.com"; }
      { list = "@th4@c2paint.com"; }
      { list = "@rruffolo@impactplus.com"; }
      { list = "@sbaiocchi@impactplus.com"; }
      { list = "@marketing@impactplus.com"; }
      { list = "@mary@grouphealthcareandrxhorizon.shop"; }
      { list = "@Team=flathead.ai@mg.flathead.ai"; }
      { list = "@hello@camelcitymill.com"; }
      { list = "@timbertech@timbertech.com"; }
      { list = "@info@prosperamt.org"; }
      { list = "general.mail.perplexity.ai@team@mail.perplexity.ai"; }
      { list = "@service@supernote.com"; }
      { list = "1288ec53061651dff6a2c5faf.392069.list-id.mcsv.net@b2b@owenhouse.com"; }
      { list = "@news@vagaro.com"; }
      { list = "@illinoistollway@email.openroadsahead.com"; }
      { list = "@sacerdoti@pipedream.com"; }
      { list = "b3f5f5cfacc9d7c44a345b240.538302.list-id.mcsv.net@mark.ahmed@oshatrainingschool.com"; }
      { list = "5364742648.1795281@benchmarkemail.com@jessica@1B64D1.clients.bmsend.com"; }
      { list = "@info@skinrockusa.com"; }
      { list = "@team@emails.hostinger.com"; }
      { list = "@sales@brand.faire.com"; }
      { list = "@sales@tigersteethblades.com"; }
      { list = "@help@profitabletradie.com"; }
      { list = "@marti.amos@theprofessionalbuilder.com"; }
      { list = "classicalideals.substack.com@classicalideals@substack.com"; }
      { list = "@muskyman55.gmail.com@bounces.cloud.em.secureserver.net"; }
      { list = "@info@all-clad.com"; }
      { list = "@montanaaleworks@mg.owner.com"; }
      { list = "@chelsea.c@ifttt.com"; }
      { list = "@brother@my.brother.com"; }
      { list = "@nick@nickpollard.com"; }
      { list = "@marketing@houzz.com"; }
      { list = "@community@getjobber.com"; }
      { list = "@info@e.gavinnewsom.com"; }
      { list = "@no-reply@otter.ai"; }
      { list = "@reviews@yotpo.com"; }
      { list = "@newsletter@rumble.com"; }
      # Preserve the original list tests too, even when From happens to match
      # a domain/address above. A relay can change From without changing list-id.
      { list = "@newsletter@mailing.hibid.com"; }
      { list = "@support=agesafeamerica.com@email.agesafeamerica.com"; }
      { list = "@info-captivatedesigns.com@shared1.ccsend.com"; }
      { list = "mv150-default.jonloomer.com@me@jonloomer.com"; }
      { list = "@do-not-reply@mail.amrlocal.com"; }
      { list = "@homedepotpro@mg.homedepot.com"; }
      { list = "@nicole-captivatedesigns.com@shared1.ccsend.com"; }
      { list = "@HomeDepotCustomerCare@mg.homedepot.com"; }
      { list = "@news@jimgreenfootwear.com"; }
      { list = "@hyperfocus=nextlevelsystems.co@mail.nextlevelsystems.co"; }
      { list = "@support@harborinno.com"; }
      { list = "@promotions@mailing.hibid.com"; }
      { list = "5f37cdd1d3c7111cfd6088ed0.53281.list-id.mcsv.net@contact@hamradioprep.com"; }
      { list = "@hello-hardybrands.com@shared1.ccsend.com"; }
      { list = "@UnitedAirlines@enews.united.com"; }
      { list = "@YardHouse@e.yardhouse.com"; }
      { list = "@Dell_Rewards@comms.dell.com"; }
      { list = "@newsletter@auctions.hibid.com"; }
      { list = "@service@shawncraft.com"; }
    ];

    # Guard on trash entries, enforced in lib.nix at evaluation.
    protected = {
      # never junk, for either producer: own/work mail and senders Eric keeps
      # (2026-09-29: SSL/SEO reports, WordPress login alerts, Meta business).
      # A domain protects itself and its subdomains; an address protects only itself.
      strict = [
        "iheartwoodcraft.com" "contractorcto.com" "datax.to"
        "semrush.com" "limitloginattempts.com" "mail.instagram.com"
        "contractorcto@gmail.com"
      ];
      # account notices: no whole-domain entry; reviewed exact marketing
      # addresses (e.g. no-reply@news.proton.me) are allowed
      domainOnly = [ "proton.me" ];
    };
  };
}
