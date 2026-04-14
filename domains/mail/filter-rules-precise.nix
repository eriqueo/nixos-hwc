# Auto-generated mail filter rules — 2026-04-05
# Sources: notmuch inbox analysis + manual tag:trash pattern mining
#
# Usage: import this file in your profile and merge with existing rules.
#
#   hwc.mail.notmuch.rules = {
#     trashSenders = (import ./filter-rules-precise.nix).trashSenders;
#     notificationSenders = [
#       # keep defaults:
#       "no-reply@" "noreply@" "notifications@" "notices@" "github.com"
#     ] ++ (import ./filter-rules-precise.nix).notificationSenders;
#   };
#
# NOTE: notificationSenders REPLACES defaults (not appends), so include
# the defaults when overriding. trashSenders defaults to [] so no conflict.
{
  # ── Combined trashSenders for hwc.mail.notmuch.rules ────────────────────
  # Flat list: domains + addresses + gmail spam. Use directly.
  trashSenders = [

    # ── Marketing relays ──────────────────────────────────────────────────
    "shared1.ccsend.com"          # Constant Contact marketing relay
    "send.mailerlite.eu"          # MailerLite marketing relay
    "mail.genierocket.com"        # GenieRocket marketing relay
    "t.shopifyemail.com"          # Shopify store marketing emails

    # ── Coaching / drip campaigns ─────────────────────────────────────────
    "theprofessionalbuilder.com"  # Builder coaching drip
    "profitabletradie.com"        # Contractor coaching ("FREE GUIDE", etc.)
    "thecontractorfight.com"      # Contractor coaching drip (Tom Reber)
    "email.hammerandgrind.com"    # "Contractor Profit Blueprint" marketing
    "nextlevelsystems.co"         # ADHD coaching drip funnel
    "seriousgrit.com"             # Coaching marketing
    "comms.contractorcto.com"     # ContractorCTO marketing drip

    # ── Networking / directory spam ───────────────────────────────────────
    "alignable.com"               # Small business networking spam
    "bniconnectglobal.com"        # BNI networking marketing

    # ── Product / SaaS marketing ──────────────────────────────────────────
    "trainsemail.com"             # Model railroad marketing newsletters
    "shapr3d.com"                 # CAD software marketing drip
    "limitloginattempts.com"      # WordPress plugin upsell drip
    "loox.io"                     # SaaS review marketing
    "mail.instagram.com"          # Instagram re-engagement spam

    # ── Retail / consumer marketing subdomains ────────────────────────────
    "enews.united.com"            # United Airlines marketing (NOT transactional)
    "your.cvs.com"                # CVS retail marketing/promos
    "insideapple.apple.com"       # Apple marketing (TV, Fitness+, Creator Studio)
    "mg.homedepot.com"            # Home Depot marketing ("GOAL VIBES", "FIFA")
    "mailing.hibid.com"           # HiBid auction newsletter/promos
    "service.hbomax.com"          # HBO Max marketing
    "mail.hbomax.com"             # HBO Max marketing
    "emailinfo.bestbuy.com"       # Best Buy marketing
    "e.acmetools.com"             # Acme Tools marketing
    "service.jossandmain.com"     # Joss & Main furniture marketing
    "rs.email.nextdoor.com"       # Nextdoor marketing
    "is.email.nextdoor.com"       # Nextdoor marketing
    "hs.email.nextdoor.com"       # Nextdoor marketing

    # ── Cold outreach domains ─────────────────────────────────────────────
    "idealcostestimate.pro"       # Construction estimating cold outreach
    "takeoffconsultants.net"      # Construction estimating cold outreach
    "bestsoftwaredevelopmentcompany.com" # Dev outsourcing cold outreach
    "webappconsultant.com"        # Web dev cold outreach
    "creativeweb.services"        # Web dev cold outreach
    "mobwebify.com"               # Web dev cold outreach
    "rankawe.com"                 # SEO cold outreach
    "adcomt.com"                  # Advertising cold outreach
    "powerhousenow.com"           # Business cold outreach
    "stantaylor.com"              # Cold outreach
    "harborinno.com"              # Cold outreach
    "shorefundingusa.net"         # Funding cold outreach
    "southerngulfcapital.com"     # Financial cold outreach
    "floridagulfcapital.com"      # Financial cold outreach

    # ── Pure spam / junk domains ──────────────────────────────────────────
    "sedioliniauto.com"           # Foreign language spam
    "treflio.com"                 # Travel/camping spam
    "snorelessnow.com"            # Product spam
    "nupent.com"                  # Spam
    "marketsshelfs.com"           # Spam
    "marblerenew.com"             # Product spam
    "hmmarblesink.com"            # Product spam
    "mails.zoloftlab.info"        # Pharma spam
    "mails.ukcz.info"            # Spam
    "mails.postlight.info"        # Spam
    "jarry.cc"                    # Spam
    "inv.alid.pw"                 # Spam
    "informatel.nl"               # Spam
    "hsmgroup.directory"          # Spam
    "heifetz.xyz"                 # Spam
    "go1001000.com"               # Spam
    "flicket.io"                  # Spam
    "finanzkanzlei-adamietz.de"   # Foreign spam
    "bmyincplans.com"             # Spam
    "nasilyan.com"                # Spam
    "nasentc.com"                 # Spam
    "microkits.net"               # Spam
    "econgobooks.com"             # Spam
    "terrance.allofti.me"         # Spam
    "sttlogisticsgroup.com"       # Spam
    "ellasbubbles.com"            # Product spam
    "jimgreenfootwear.com"        # Product spam
    "powernailglobal.com"         # Product spam
    "klingspor.com"               # Tools marketing spam
    "fensterusa.com"              # Product spam
    "agesafeamerica.com"          # Product marketing
    "mail.amrlocal.com"           # Local marketing spam
    "hamradioprep.com"            # Product marketing

    # ── Address-level trash (mixed-use domains) ───────────────────────────
    "marketing@thumbtack.com"
    "do-not-reply@customer.thumbtack.com"
    "marketing@narihq.org"
    "info@narihq.org"
    "noreply@angi.com"
    "no-reply@offers.proton.me"
    "no-reply@news.proton.me"
    "business-updates@proton.me"

    # ── Gmail estimating cold-outreach (inbox + archive) ──────────────────
    # Pattern: *estimat*, *takeoff*, *bid*, *construct* @gmail.com
    # These rotate constantly — consider extending rules.nix with regex.
    "will.constructiontakeoffs@gmail.com"
    "wesley.biddingestimation@gmail.com"
    "tyler.primeestimation37@gmail.com"
    "tyler.speedyestimates@gmail.com"
    "aries.bidestimations@gmail.com"
    "theodore.titanestimates@gmail.com"
    "teddygeiger473@gmail.com"
    "valentinogonzalez531@gmail.com"
    "stimbidsaim76@gmail.com"
    "sandy.projectplansbreakdown@gmail.com"
    "russ.estimateandconstruct@gmail.com"
    "rowen.globalbids3367@gmail.com"
    "robert.precisescopeestimating@gmail.com"
    "reyes.estimategeneral@gmail.com"
    "paul.coreestimations@gmail.com"
    "olivia.estimanians2@gmail.com"
    "oben.swiftestimations@gmail.com"
    "noah.estimations3@gmail.com"
    "schaible.aimestimating@gmail.com"
    "matthew.primeestimation7@gmail.com"
    "markus.yoursestimates@gmail.com"
    "lucas.precisescopeestimations@gmail.com"
    "lisaphoenixestimation@gmail.com"
    "liam.parker.yoursestimatings@gmail.com"
    "liam.constructiontakeoff1155@gmail.com"
    "knox.constructionetakeoff19@gmail.com"
    "k.aimestimatings@gmail.com"
    "kari.makestimating@gmail.com"
    "julian.globalestimation@gmail.com"
    "joshue.aquaestimating@gmail.com"
    "joseph.constructionbidss@gmail.com"
    "john.aceccuracy.takeoff@gmail.com"
    "jason.usbasedprojects555@gmail.com"
    "jack.constructingestimates@gmail.com"
    "jack.contructionestimatesof@gmail.com"
    "jack.globalestimatings@gmail.com"
    "grant.aimestimate7@gmail.com"
    "gloria.perfectestimation@gmail.com"
    "fisher.aimestimating@gmail.com"
    "elijah.aimestimatestakeof@gmail.com"
    "edward.primeestimation45@gmail.com"
    "dominick.constructiontakeoff@gmail.com"
    "david.bidproestimation45@gmail.com"
    "daniel.estimation15@gmail.com"
    "daniel17estimationhubinc@gmail.com"
    "dan.30esthubinc@gmail.com"
    "chris.constructionbidding@gmail.com"
    "chrisjohn.takeoff@gmail.com"
    "cjohn.estimatings@gmail.com"
    "canon.estimates@gmail.com"
    "benjamincharlieestimation@gmail.com"
    "archieleo.yourstakeoff@gmail.com"
    "antonio.estimatingcraftllc@gmail.com"
    "anthony.superiorestimating.us@gmail.com"
    "andrewmasonglobelbids@gmail.com"
    "alan.speedybid@gmail.com"
    "adan.americanestimation7@gmail.com"
    "aimestimators.us@gmail.com"
    "561.estimation@gmail.com"
    "mike.construction.supervisor@gmail.com"
    "scott.constructions24@gmail.com"
    "rochelleswiftarchitecture@gmail.com"
    "lanarchitectservices@gmail.com"
    "johnn.swiftarchitecture@gmail.com"
    "ankita.webservice123@gmail.com"
    "contractorcto@gmail.com"
    "shrek.ressurrected@gmail.com"
    "tymtomojaydon6743@gmail.com"
    # From archive/trash:
    "randi.fasttakeoff@gmail.com"
    "noah.globalestimates87@gmail.com"
    "greg.globalestimating@gmail.com"
    "emmett.civilstructialplanss190@gmail.com"
    "aaron.bidsandconstruction@gmail.com"
    "abttakeoff.chrisj@gmail.com"
    "charles.eliteworksconsulting@gmail.com"
    "mike.gracegroupllc4@gmail.com"
    "makerankseoservice@gmail.com"
    "secure.paypal.03@gmail.com"
    "levi.service56@gmail.com"
  ];

  # ── Additional notification senders (merge with defaults) ───────────────
  # The defaults already include: no-reply@ noreply@ notifications@ notices@ github.com
  # These are ADDITIONS — when setting the option, include defaults too:
  #   notificationSenders = [ "no-reply@" "noreply@" "notifications@" "notices@" "github.com" ]
  #                      ++ (import ./filter-rules-precise.nix).notificationSenders;
  notificationSenders = [
    "replit.com"      # Product updates, retention notices
    "sketchup.com"    # Product update emails
    "pinecone.io"     # Product updates and webinar invites
    "linkedin.com"    # LinkedIn notifications (security-noreply already caught, but catches all)
  ];
}
