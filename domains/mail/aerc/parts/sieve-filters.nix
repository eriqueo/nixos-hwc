# domains/mail/aerc/parts/sieve-filters.nix
# Auto-generated 2026-04-05 from inbox + archive sender analysis.
# Produces attrset for hwc.mail.aerc.sieve.filters — each key becomes
# a separate .sieve file, all bundled into bundle.sieve for Proton paste.
#
# Proton Sieve notes:
#   - address :domain  → matches domain part of From
#   - address :is      → matches full address
#   - header :contains → substring on raw header (fallback)
#   - fileinto "Trash" → Proton Trash folder
#   - fileinto "Archive" → Proton Archive (All Mail)
{
  # ────────────────────────────────────────────────────────────────────────
  # 20 — Marketing relays
  # ────────────────────────────────────────────────────────────────────────
  "20-trash-marketing-relays.sieve" = ''
    require ["fileinto"];
    # Constant Contact, MailerLite, GenieRocket, Shopify relay domains
    if anyof(
      address :domain "from" "shared1.ccsend.com",
      address :domain "from" "send.mailerlite.eu",
      address :domain "from" "mail.genierocket.com",
      address :domain "from" "t.shopifyemail.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 21 — Coaching / drip campaigns
  # ────────────────────────────────────────────────────────────────────────
  "21-trash-coaching-drip.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "theprofessionalbuilder.com",
      address :domain "from" "profitabletradie.com",
      address :domain "from" "thecontractorfight.com",
      address :domain "from" "email.hammerandgrind.com",
      address :domain "from" "nextlevelsystems.co",
      address :domain "from" "seriousgrit.com",
      address :domain "from" "comms.contractorcto.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 22 — Networking / directory spam
  # ────────────────────────────────────────────────────────────────────────
  "22-trash-networking-spam.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "alignable.com",
      address :domain "from" "bniconnectglobal.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 23 — Product / SaaS marketing
  # ────────────────────────────────────────────────────────────────────────
  "23-trash-product-saas.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "trainsemail.com",
      address :domain "from" "shapr3d.com",
      address :domain "from" "limitloginattempts.com",
      address :domain "from" "loox.io",
      address :domain "from" "mail.instagram.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 24 — Retail / consumer marketing subdomains
  # ────────────────────────────────────────────────────────────────────────
  "24-trash-retail-marketing.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "enews.united.com",
      address :domain "from" "your.cvs.com",
      address :domain "from" "insideapple.apple.com",
      address :domain "from" "mg.homedepot.com",
      address :domain "from" "mailing.hibid.com",
      address :domain "from" "service.hbomax.com",
      address :domain "from" "mail.hbomax.com",
      address :domain "from" "emailinfo.bestbuy.com",
      address :domain "from" "e.acmetools.com",
      address :domain "from" "service.jossandmain.com",
      address :domain "from" "rs.email.nextdoor.com",
      address :domain "from" "is.email.nextdoor.com",
      address :domain "from" "hs.email.nextdoor.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 25 — Cold outreach domains
  # ────────────────────────────────────────────────────────────────────────
  "25-trash-cold-outreach.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "idealcostestimate.pro",
      address :domain "from" "takeoffconsultants.net",
      address :domain "from" "bestsoftwaredevelopmentcompany.com",
      address :domain "from" "webappconsultant.com",
      address :domain "from" "creativeweb.services",
      address :domain "from" "mobwebify.com",
      address :domain "from" "rankawe.com",
      address :domain "from" "adcomt.com",
      address :domain "from" "powerhousenow.com",
      address :domain "from" "stantaylor.com",
      address :domain "from" "harborinno.com",
      address :domain "from" "shorefundingusa.net",
      address :domain "from" "southerngulfcapital.com",
      address :domain "from" "floridagulfcapital.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 26 — Pure spam / junk domains
  # ────────────────────────────────────────────────────────────────────────
  "26-trash-spam-junk.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "sedioliniauto.com",
      address :domain "from" "treflio.com",
      address :domain "from" "snorelessnow.com",
      address :domain "from" "nupent.com",
      address :domain "from" "marketsshelfs.com",
      address :domain "from" "marblerenew.com",
      address :domain "from" "hmmarblesink.com",
      address :domain "from" "mails.zoloftlab.info",
      address :domain "from" "mails.ukcz.info",
      address :domain "from" "mails.postlight.info",
      address :domain "from" "jarry.cc",
      address :domain "from" "inv.alid.pw",
      address :domain "from" "informatel.nl",
      address :domain "from" "hsmgroup.directory",
      address :domain "from" "heifetz.xyz",
      address :domain "from" "go1001000.com",
      address :domain "from" "flicket.io",
      address :domain "from" "finanzkanzlei-adamietz.de",
      address :domain "from" "bmyincplans.com",
      address :domain "from" "nasilyan.com",
      address :domain "from" "nasentc.com",
      address :domain "from" "microkits.net",
      address :domain "from" "econgobooks.com",
      address :domain "from" "terrance.allofti.me",
      address :domain "from" "sttlogisticsgroup.com",
      address :domain "from" "ellasbubbles.com",
      address :domain "from" "jimgreenfootwear.com",
      address :domain "from" "powernailglobal.com",
      address :domain "from" "klingspor.com",
      address :domain "from" "fensterusa.com",
      address :domain "from" "agesafeamerica.com",
      address :domain "from" "mail.amrlocal.com",
      address :domain "from" "hamradioprep.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 27 — Mixed-use domains (address-level only)
  # ────────────────────────────────────────────────────────────────────────
  "27-trash-address-level.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :is "from" "marketing@thumbtack.com",
      address :is "from" "do-not-reply@customer.thumbtack.com",
      address :is "from" "marketing@narihq.org",
      address :is "from" "info@narihq.org",
      address :is "from" "noreply@angi.com",
      address :is "from" "no-reply@offers.proton.me",
      address :is "from" "no-reply@news.proton.me",
      address :is "from" "business-updates@proton.me"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 28 — Gmail estimating cold-outreach
  #      Pattern: *estimat*, *takeoff*, *bid*, *construct* @gmail.com
  #      These rotate constantly — the address list is a snapshot.
  # ────────────────────────────────────────────────────────────────────────
  "28-trash-gmail-estimating-spam.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :is "from" "will.constructiontakeoffs@gmail.com",
      address :is "from" "wesley.biddingestimation@gmail.com",
      address :is "from" "tyler.primeestimation37@gmail.com",
      address :is "from" "tyler.speedyestimates@gmail.com",
      address :is "from" "aries.bidestimations@gmail.com",
      address :is "from" "theodore.titanestimates@gmail.com",
      address :is "from" "teddygeiger473@gmail.com",
      address :is "from" "valentinogonzalez531@gmail.com",
      address :is "from" "stimbidsaim76@gmail.com",
      address :is "from" "sandy.projectplansbreakdown@gmail.com",
      address :is "from" "russ.estimateandconstruct@gmail.com",
      address :is "from" "rowen.globalbids3367@gmail.com",
      address :is "from" "robert.precisescopeestimating@gmail.com",
      address :is "from" "reyes.estimategeneral@gmail.com",
      address :is "from" "paul.coreestimations@gmail.com",
      address :is "from" "olivia.estimanians2@gmail.com",
      address :is "from" "oben.swiftestimations@gmail.com",
      address :is "from" "noah.estimations3@gmail.com",
      address :is "from" "schaible.aimestimating@gmail.com",
      address :is "from" "matthew.primeestimation7@gmail.com",
      address :is "from" "markus.yoursestimates@gmail.com",
      address :is "from" "lucas.precisescopeestimations@gmail.com",
      address :is "from" "lisaphoenixestimation@gmail.com",
      address :is "from" "liam.parker.yoursestimatings@gmail.com",
      address :is "from" "liam.constructiontakeoff1155@gmail.com",
      address :is "from" "knox.constructionetakeoff19@gmail.com",
      address :is "from" "k.aimestimatings@gmail.com",
      address :is "from" "kari.makestimating@gmail.com",
      address :is "from" "julian.globalestimation@gmail.com",
      address :is "from" "joshue.aquaestimating@gmail.com",
      address :is "from" "joseph.constructionbidss@gmail.com",
      address :is "from" "john.aceccuracy.takeoff@gmail.com",
      address :is "from" "jason.usbasedprojects555@gmail.com",
      address :is "from" "jack.constructingestimates@gmail.com",
      address :is "from" "jack.contructionestimatesof@gmail.com",
      address :is "from" "jack.globalestimatings@gmail.com",
      address :is "from" "grant.aimestimate7@gmail.com",
      address :is "from" "gloria.perfectestimation@gmail.com",
      address :is "from" "fisher.aimestimating@gmail.com",
      address :is "from" "elijah.aimestimatestakeof@gmail.com",
      address :is "from" "edward.primeestimation45@gmail.com",
      address :is "from" "dominick.constructiontakeoff@gmail.com",
      address :is "from" "david.bidproestimation45@gmail.com",
      address :is "from" "daniel.estimation15@gmail.com",
      address :is "from" "daniel17estimationhubinc@gmail.com",
      address :is "from" "dan.30esthubinc@gmail.com",
      address :is "from" "chris.constructionbidding@gmail.com",
      address :is "from" "chrisjohn.takeoff@gmail.com",
      address :is "from" "cjohn.estimatings@gmail.com",
      address :is "from" "canon.estimates@gmail.com",
      address :is "from" "benjamincharlieestimation@gmail.com",
      address :is "from" "archieleo.yourstakeoff@gmail.com",
      address :is "from" "antonio.estimatingcraftllc@gmail.com",
      address :is "from" "anthony.superiorestimating.us@gmail.com",
      address :is "from" "andrewmasonglobelbids@gmail.com",
      address :is "from" "alan.speedybid@gmail.com",
      address :is "from" "adan.americanestimation7@gmail.com",
      address :is "from" "aimestimators.us@gmail.com",
      address :is "from" "561.estimation@gmail.com",
      address :is "from" "mike.construction.supervisor@gmail.com",
      address :is "from" "scott.constructions24@gmail.com",
      address :is "from" "rochelleswiftarchitecture@gmail.com",
      address :is "from" "lanarchitectservices@gmail.com",
      address :is "from" "johnn.swiftarchitecture@gmail.com",
      address :is "from" "ankita.webservice123@gmail.com",
      address :is "from" "contractorcto@gmail.com",
      address :is "from" "shrek.ressurrected@gmail.com",
      address :is "from" "tymtomojaydon6743@gmail.com",
      address :is "from" "randi.fasttakeoff@gmail.com",
      address :is "from" "noah.globalestimates87@gmail.com",
      address :is "from" "greg.globalestimating@gmail.com",
      address :is "from" "emmett.civilstructialplanss190@gmail.com",
      address :is "from" "aaron.bidsandconstruction@gmail.com",
      address :is "from" "abttakeoff.chrisj@gmail.com",
      address :is "from" "charles.eliteworksconsulting@gmail.com",
      address :is "from" "mike.gracegroupllc4@gmail.com",
      address :is "from" "makerankseoservice@gmail.com",
      address :is "from" "secure.paypal.03@gmail.com",
      address :is "from" "levi.service56@gmail.com"
    ) {
      fileinto "Trash";
      stop;
    }
  '';

  # ────────────────────────────────────────────────────────────────────────
  # 30 — Notifications → Archive (not trash)
  # ────────────────────────────────────────────────────────────────────────
  "30-archive-notifications.sieve" = ''
    require ["fileinto"];
    if anyof(
      address :domain "from" "replit.com",
      address :domain "from" "sketchup.com",
      address :domain "from" "pinecone.io",
      address :domain "from" "linkedin.com"
    ) {
      fileinto "Archive";
      stop;
    }
  '';
}
