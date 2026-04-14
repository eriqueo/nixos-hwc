# Email Filter Audit — 2026-04-05

Analysis of notmuch inbox + archive (tag:trash) to identify high-volume senders for auto-trash and auto-archive rules.

## Current Defaults (already active)

| Rule | Patterns |
|------|----------|
| Newsletter (-inbox) | `newsletter@`, `news@`, `updates@`, `digest@`, `list@`, `mailer@` |
| Notification (-inbox) | `no-reply@`, `noreply@`, `notifications@`, `notices@`, `github.com` |
| Finance (-inbox) | `amazon.com`, `paypal.com`, `stripe.com`, `squareup.com`, `intuit.com`, `quickbooks`, `chase.com`, `bankofamerica.com` |
| Trash (-inbox -unread) | *(empty — this audit populates it)* |

## Sender Classification

### Domain-level TRASH (all addresses are unwanted)

| Domain | Count | Type | Reason |
|--------|-------|------|--------|
| shared1.ccsend.com | 7 | Marketing relay | Constant Contact — all promos (Vamoose Bus, Cogir, Captivate, Bluehost) |
| trainsemail.com | 4+ | Newsletter/marketing | Model railroad promos ("Treat Yourself", "Father's Day", "New Video Series") |
| alignable.com | 3 | Networking spam | "You're invited to a virtual networking event" × N |
| enews.united.com | 4 | Airline marketing | MileagePlus promos, partner offers (NOT transactional united.com) |
| your.cvs.com | 2 | Retail marketing | "70% Off Canvas", "3x Savings" promos |
| mail.instagram.com | 2 | Re-engagement | "We've made it easy to get back on Instagram" × N |
| shapr3d.com | 2 | SaaS drip | "Where will your design go next?" onboarding/marketing |
| theprofessionalbuilder.com | 2 | Coaching drip | "Stop running your $3M company alone", "Still not charging for quotes?" |
| idealcostestimate.pro | 2 | Cold outreach | Construction estimating cold emails |
| nextlevelsystems.co | 3 | Coaching drip | "Quick question (it's Ali)" → ADHD coaching funnel |
| limitloginattempts.com | 3 | SaaS upsell drip | "ACTION REQUIRED - Update Your Payment Info" scare tactics |
| send.mailerlite.eu | 1 | Marketing relay | MailerLite relay (Caplan's Auctions promo) |
| mail.genierocket.com | 1 | Marketing relay | GenieRocket relay (auction marketing) |

### Address-level TRASH

| Address | Domain | Count | Reason |
|---------|--------|-------|--------|
| marketing@thumbtack.com | thumbtack.com | 1 | "Diversify your offerings and get more leads" |
| do-not-reply@customer.thumbtack.com | thumbtack.com | 1 | Thumbtack marketing |
| marketing@narihq.org | narihq.org | 1 | NARI marketing (keep education/certification addresses) |
| info@narihq.org | narihq.org | 1 | NARI general marketing |
| noreply@angi.com | angi.com | 1 | Angi marketing (keep human sales contacts) |
| no-reply@offers.proton.me | proton.me | 1 | Proton promotional offers |
| no-reply@news.proton.me | proton.me | 1 | Proton product news |
| business-updates@proton.me | proton.me | 1 | Proton business marketing |

### Gmail Cold-Outreach Estimating Spam (60+ addresses)

Massive pattern: construction estimating services using gmail addresses with keywords like "estimation", "takeoff", "bid", "construct" in the local part. All are unsolicited cold outreach.

**Pattern**: `*estimat*@gmail.com`, `*takeoff*@gmail.com`, `*bid*@gmail.com`, `*construct*@gmail.com`

> **NOTE**: The current rules engine does NOT support pattern/regex matching. Each address must be listed individually. See "Recommended Improvements" below for a pattern-based approach.

| Address | Subject Sample |
|---------|---------------|
| will.constructiontakeoffs@gmail.com | "Cost components in GC vs. single trade estimates" |
| wesley.biddingestimation@gmail.com | "A Better Way to Handle Takeoffs" |
| tyler.primeestimation37@gmail.com | "Boost Margins" |
| tyler.speedyestimates@gmail.com | "Precise cost estimations and detailed take-offs" |
| aries.bidestimations@gmail.com | "Construction Projects!" |
| theodore.titanestimates@gmail.com | "Confident Pricing Strategy in Remodeler" |
| teddygeiger473@gmail.com | "Building Estimates" |
| valentinogonzalez531@gmail.com | "Project Pricing Quotes" |
| stimbidsaim76@gmail.com | (estimating spam) |
| sandy.projectplansbreakdown@gmail.com | (estimating spam) |
| russ.estimateandconstruct@gmail.com | (estimating spam) |
| rowen.globalbids3367@gmail.com | (estimating spam) |
| robert.precisescopeestimating@gmail.com | (estimating spam) |
| reyes.estimategeneral@gmail.com | (estimating spam) |
| paul.coreestimations@gmail.com | (estimating spam) |
| olivia.estimanians2@gmail.com | (estimating spam) |
| oben.swiftestimations@gmail.com | (estimating spam) |
| noah.estimations3@gmail.com | (estimating spam) |
| schaible.aimestimating@gmail.com | (estimating spam) |
| matthew.primeestimation7@gmail.com | (estimating spam) |
| markus.yoursestimates@gmail.com | (estimating spam) |
| lucas.precisescopeestimations@gmail.com | (estimating spam) |
| lisaphoenixestimation@gmail.com | (estimating spam) |
| liam.parker.yoursestimatings@gmail.com | (estimating spam) |
| liam.constructiontakeoff1155@gmail.com | (estimating spam) |
| knox.constructionetakeoff19@gmail.com | (estimating spam) |
| k.aimestimatings@gmail.com | (estimating spam) |
| kari.makestimating@gmail.com | (estimating spam) |
| julian.globalestimation@gmail.com | (estimating spam) |
| joshue.aquaestimating@gmail.com | (estimating spam) |
| joseph.constructionbidss@gmail.com | (estimating spam) |
| john.aceccuracy.takeoff@gmail.com | (estimating spam) |
| jason.usbasedprojects555@gmail.com | (estimating spam) |
| jack.constructingestimates@gmail.com | (estimating spam) |
| jack.contructionestimatesof@gmail.com | (estimating spam) |
| jack.globalestimatings@gmail.com | (estimating spam) |
| grant.aimestimate7@gmail.com | (estimating spam) |
| gloria.perfectestimation@gmail.com | (estimating spam) |
| fisher.aimestimating@gmail.com | (estimating spam) |
| elijah.aimestimatestakeof@gmail.com | (estimating spam) |
| edward.primeestimation45@gmail.com | (estimating spam) |
| dominick.constructiontakeoff@gmail.com | (estimating spam) |
| david.bidproestimation45@gmail.com | (estimating spam) |
| daniel.estimation15@gmail.com | (estimating spam) |
| daniel17estimationhubinc@gmail.com | (estimating spam) |
| dan.30esthubinc@gmail.com | (estimating spam) |
| chris.constructionbidding@gmail.com | (estimating spam) |
| chrisjohn.takeoff@gmail.com | (estimating spam) |
| cjohn.estimatings@gmail.com | (estimating spam) |
| canon.estimates@gmail.com | (estimating spam) |
| benjamincharlieestimation@gmail.com | (estimating spam) |
| archieleo.yourstakeoff@gmail.com | (estimating spam) |
| antonio.estimatingcraftllc@gmail.com | (estimating spam) |
| anthony.superiorestimating.us@gmail.com | (estimating spam) |
| andrewmasonglobelbids@gmail.com | (estimating spam) |
| alan.speedybid@gmail.com | (estimating spam) |
| adan.americanestimation7@gmail.com | (estimating spam) |
| aimestimators.us@gmail.com | (estimating spam) |
| 561.estimation@gmail.com | (estimating spam) |
| mike.construction.supervisor@gmail.com | (cold outreach) |
| scott.constructions24@gmail.com | (cold outreach) |
| rochelleswiftarchitecture@gmail.com | (cold outreach) |
| lanarchitectservices@gmail.com | (cold outreach) |
| johnn.swiftarchitecture@gmail.com | (cold outreach) |
| ankita.webservice123@gmail.com | Web services cold outreach |
| contractorcto@gmail.com | "DATAx" cold outreach |
| shrek.ressurrected@gmail.com | Obvious spam |
| tymtomojaydon6743@gmail.com | "Seeking Response Today" spam |

### KEEP (no filter needed)

| Domain/Address | Count | Reason |
|----------------|-------|--------|
| api.jobtread.com | 6 | Business tool — web forms, Stripe, customer messages |
| montana.edu | 5 | Real people — university contacts (Christine Lux, Deidre Hodgson, etc.) |
| mc-ws.com | 4 | Financial advisor — McKinley Carter (real human correspondence) |
| stripe.com (invoices) | 4 | Already caught by financeSenders default |
| mail.anthropic.com | 30 | Invoices + support (invoice@ already caught by finance; support@ is real) |
| united.com (transactional) | 4 | Receipts, OTP, confirmations (NOT enews subdomain) |
| proton.me (account) | 4 | verify, recovery, wallet, calendar → security/transactional |
| icloud.com | 5 | Mixed real people + relay addresses |
| hotmail.com | 7 | Mostly low-volume unknown — not worth rules |
| quo.com (non-marketing) | 2 | New business tool onboarding — reassess later |
| gmail.com (real contacts) | ~20 | Julia O'Keefe, Eric O'Keefe, Anna Corbett, Paul Brourman, etc. |
| scorevolunteer.org | 4 | SCORE mentoring — professional development |
| narihq.org (education) | 2 | NARI certification/education (keep education@, certification@) |
| tm1.openai.com | 2 | API billing + auth codes |
| mail.zapier.com | 2 | Zap error alerts — operationally important |
| zoom.us | 2 | Webinar confirmations |
| sawhorserevolution.org | 2 | Nonprofit — real correspondence |
| prosperamt.org | 2 | Local business incubator |
| starisland.org | 2 | Personal connection newsletter |
| harborfreight.com | 2 | Purchase receipts |
| semrush.com | 4 | SEO reports — includes SSL cert expiry alerts, keep in inbox |
| remodelersontherise.com | 2 | Coaching but includes recording of Eric's appearance — KEEP for now |
| contractorgrowthnetwork.com | 3 | Business coaching — mixed marketing/real contact |

### NOTIFICATION (auto-archive, not trash)

| Domain/Address | Count | Reason |
|----------------|-------|--------|
| slack.com | 7 | Workspace notifications (sign-in alerts already caught by no-reply@ default) |
| replit.com | 2 | Product updates, retention notices |
| sketchup.com | 2 | Product update emails (not marketing spam, but not inbox-worthy) |
| pinecone.io | 3 | Product updates and webinar invites |
| linkedin.com | 4 | LinkedIn notifications (partially caught by noreply@ default) |

---

## Archive/Trash Mining (tag:trash)

Domains you've been manually trashing — now automated.

### New domain-level TRASH from archive

| Domain | Count | Type | Reason |
|--------|-------|------|--------|
| profitabletradie.com | 4 | Coaching drip | "FREE GUIDE", "DIFFICULT WORK CONVERSATIONS GUIDE" |
| insideapple.apple.com | 4 | Apple marketing | Apple TV, Fitness+, Creator Studio promos (not apple.com) |
| mg.homedepot.com | 2 | Retail marketing | "GOAL VIBES ONLY", "FIFA World Cup", "Supplies in Bulk" |
| mailing.hibid.com | 2 | Auction promos | "Top Auctions to Watch in Montana This Saturday" |
| email.hammerandgrind.com | 2 | Coaching marketing | "Contractor Profit Blueprint" |
| thecontractorfight.com | 1 | Coaching drip | Tom Reber coaching emails |
| rs/is/hs.email.nextdoor.com | 2 | Nextdoor marketing | 3 subdomains for marketing relay |
| service.hbomax.com / mail.hbomax.com | 1 | Streaming marketing | HBO Max promos |
| emailinfo.bestbuy.com | 1 | Retail marketing | Best Buy promos |
| e.acmetools.com | 1 | Retail marketing | Acme Tools promos |
| service.jossandmain.com | 1 | Retail marketing | Furniture marketing |
| t.shopifyemail.com | 1 | Marketing relay | Shopify store emails |
| sedioliniauto.com | 2 | Pure spam | Russian phishing/mold scam |
| bestsoftwaredevelopmentcompany.com | 2 | Cold outreach | "App Developer....??" |
| takeoffconsultants.net | 1 | Cold outreach | Construction estimating |
| webappconsultant.com | 1 | Cold outreach | Web dev |
| creativeweb.services | 1 | Cold outreach | Web dev |
| mobwebify.com | 1 | Cold outreach | Web dev |
| rankawe.com | 1 | Cold outreach | SEO services |
| adcomt.com | 1 | Cold outreach | Advertising |
| shorefundingusa.net | 1 | Cold outreach | Funding/loans |
| southerngulfcapital.com | 1 | Cold outreach | Financial |
| floridagulfcapital.com | 1 | Cold outreach | Financial |
| comms.contractorcto.com | 1 | Marketing drip | ContractorCTO |
| seriousgrit.com | 1 | Coaching marketing | Coaching drip |
| bniconnectglobal.com | 1 | Networking spam | BNI marketing |
| 30+ pure spam domains | 1 each | Spam/junk | mails.*.info, *.xyz, *.pw, product spam, etc. |

### Additional gmail spam from archive

| Address | Type |
|---------|------|
| randi.fasttakeoff@gmail.com | Estimation cold outreach |
| noah.globalestimates87@gmail.com | Estimation cold outreach |
| greg.globalestimating@gmail.com | Estimation cold outreach |
| emmett.civilstructialplanss190@gmail.com | Estimation cold outreach |
| aaron.bidsandconstruction@gmail.com | Estimation cold outreach |
| abttakeoff.chrisj@gmail.com | Estimation cold outreach |
| charles.eliteworksconsulting@gmail.com | Consulting cold outreach |
| mike.gracegroupllc4@gmail.com | Cold outreach |
| makerankseoservice@gmail.com | SEO cold outreach |
| secure.paypal.03@gmail.com | Phishing |
| levi.service56@gmail.com | Cold outreach |

---

## Impact Summary

| Category | Senders | Est. Messages |
|----------|---------|---------------|
| Domain-level trash (inbox) | 13 domains | ~35 |
| Domain-level trash (archive) | 55+ domains | ~80 |
| Address-level trash | 8 addresses | ~10 |
| Gmail estimating spam (combined) | 74 addresses | ~74 |
| New notification senders | 5 domains | ~15 |
| **Total trash rules** | **~150 entries** | **~200 messages** |

## Recommended Improvements

### 1. Pattern-based trash rules (requires rules.nix extension)

The gmail estimating spam follows clear patterns. Instead of 63 individual addresses, a regex/pattern rule would catch future spam too:

```
from:/@gmail\.com/ AND (subject:estimat* OR subject:takeoff* OR subject:"construction bid")
```

This requires extending `rules.nix` to support compound queries with `AND`/`OR` and subject matching in the trash rule. Flag: **compound rule needed**.

### 2. Subject-based auto-trash

Subjects containing these patterns are reliably trash:
- "% off", "sale ends", "free trial", "upgrade now"
- "virtual networking event" (Alignable pattern)
- "easy to get back on Instagram"

This also requires extending rules.nix with `mkSubj` support in trash rules.
