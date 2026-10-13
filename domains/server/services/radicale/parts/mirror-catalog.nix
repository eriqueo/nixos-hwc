# domains/server/services/radicale/parts/mirror-catalog.nix
#
# The one list of read-only calendar mirrors in Radicale: collection id →
# feed secret, name, colour. Pure data, so both lanes read the same list:
#   - the server: default of hwc.server.services.radicale.mirrors (../index.nix),
#     which parts/mirrors.nix turns into VEVENT-only collections + a sync timer;
#   - every khal machine: default of hwc.mail.calendar.radicale.extraCollections
#     (domains/mail/calendar/index.nix) — the VEVENT pair pins these ids.
# Add or remove a mirror here only; nothing else names the ids.
#
# Task clients need no copy: the collections are VEVENT-only, and todui, the
# phone, the wall and voice all skip collections that take no VTODO.

{
  cto           = { secret = "cto-ical-link";    displayName = "ContractorCTO"; color = "#FF9F0A"; };
  proton-work   = { secret = "proton-ical-link"; displayName = "Proton work";   color = "#BF5AF2"; };
  google-family = { secret = "hwcmt-ical-link";  displayName = "Google family"; color = "#30D158"; };
}
