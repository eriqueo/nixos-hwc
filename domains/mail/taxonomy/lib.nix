# domains/mail/taxonomy/lib.nix
#
# Pure derivation helpers over data.nix — per-consumer views of the canonical
# taxonomy. Importable from both lanes (`import .../taxonomy/lib.nix { inherit lib; }`).
# No options and no runtime artifact producer.
{ lib, data ? import ./data.nix }:   # `data` is injectable for the guard's check
let
  s = data.senders;

  # Normalise every trash entry to { sender | list, scope }.
  norm = e:
    if builtins.isString e then { sender = e; scope = "both"; }
    else if e ? list then { list = e.list; scope = "proton"; }
    else { scope = "both"; } // e;

  normalised = map norm s.trash;

  isAddress = x: lib.hasInfix "@" x;
  domainOf = x: lib.last (lib.splitString "@" x);

  # A domain entry covers itself and every subdomain, so it collides with a
  # protected domain when either one is a suffix of the other on a dot boundary.
  domainHits = d: p: d == p || lib.hasSuffix ".${p}" d || lib.hasSuffix ".${d}" p;
  # An exact address only touches its own domain.
  addressHits = a: p: let d = domainOf a; in d == p || lib.hasSuffix ".${p}" d;

  # A protected address is hit by itself or by any domain entry covering it;
  # protected domains use the rules above.
  hits = x: p:
    if isAddress p then
      (if isAddress x then x == lib.toLower p
       else let d = domainOf (lib.toLower p); in d == x || lib.hasSuffix ".${x}" d)
    else if isAddress x then addressHits x p
    else domainHits x p;

  violates = e:
    let x = lib.toLower e.sender; in
    e ? sender && (
      lib.any (hits x) s.protected.strict
      || (!isAddress x && lib.any (domainHits x) s.protected.domainOnly));

  # Every consumer view derives from the checked list, so a protected sender
  # fails evaluation instead of reaching either trash producer.
  entries =
    let bad = lib.filter violates normalised; in
    if bad == [] then normalised
    else throw "taxonomy: trash entries match a protected domain: ${
      lib.concatMapStringsSep ", " (e: e.sender) bad}";
  inScope = scope: lib.filter (e: e.scope == "both" || e.scope == scope) entries;

  protonChecked = inScope "proton";
  protonSenders = lib.filter (e: e ? sender) protonChecked;
in
{
  inherit data;

  derived = {
    # Gmail janitor wire: plain strings, unchanged shape. It does not classify
    # or place local mail.
    trashSenders = map (e: e.sender) (lib.filter (e: e ? sender) (inScope "gmail"));

    # Proton Sieve view, split by match kind (aerc/parts/sieve-filters.nix).
    protonTrash = {
      domains   = map (e: e.sender) (lib.filter (e: !isAddress e.sender) protonSenders);
      addresses = map (e: e.sender) (lib.filter (e: isAddress e.sender) protonSenders);
      lists     = map (e: e.list) (lib.filter (e: e ? list) protonChecked);
    };
  };
}
