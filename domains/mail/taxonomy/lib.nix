# domains/mail/taxonomy/lib.nix
#
# Pure derivation helpers over data.nix — per-consumer views of the canonical
# taxonomy. Importable from both lanes (`import .../taxonomy/lib.nix { inherit lib; }`).
# No options and no runtime artifact producer.
{ lib, data ? import ./data.nix }:   # `data` is injectable for the guard's check
let
  s = data.senders;

  # Parse entry shapes once into a tagged match kind. Reject ambiguous entries
  # and misspelled scopes before either consumer sees the list.
  norm = e:
    let
      raw = if builtins.isString e then { sender = e; } else e;
      attr = builtins.isAttrs raw;
      sender = attr && raw ? sender;
      list = attr && raw ? list;
      scope = raw.scope or (if list then "proton" else "both");
      value = if sender then raw.sender else raw.list;
      validShape = attr && sender != list
        && lib.all (key: lib.elem key [ "sender" "list" "scope" ]) (builtins.attrNames raw);
      validValue = builtins.isString value && value != ""
        && builtins.match ".*[[:space:]].*" value == null;
      validSender = !sender || builtins.match
        "([A-Za-z0-9.!#$%&'+/=?^_`{|}~-]+@)?[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*" value != null;
    in
    if !validShape then throw "taxonomy: trash entry needs exactly one sender or list"
    else if !(lib.elem scope [ "both" "gmail" "proton" ]) || (list && scope != "proton")
      then throw "taxonomy: invalid trash scope"
    else if !validValue || !validSender then throw "taxonomy: invalid trash match value"
    else { kind = if list then "list" else if isAddress value then "address" else "domain";
      value = lib.toLower value; inherit scope; };

  normalised = map norm s.trash;

  isAddress = x: lib.hasInfix "@" x;
  domainOf = x: lib.last (lib.splitString "@" x);
  protected = lib.mapAttrs (_: map lib.toLower) s.protected;

  # A domain entry covers itself and every subdomain, so it collides with a
  # protected domain when either one is a suffix of the other on a dot boundary.
  domainHits = d: p: d == p || lib.hasSuffix ".${p}" d || lib.hasSuffix ".${d}" p;
  # An exact address only touches its own domain.
  addressHits = a: p: let d = domainOf a; in d == p || lib.hasSuffix ".${p}" d;

  # A protected address is hit by itself or by any domain entry covering it;
  # protected domains use the rules above.
  hits = x: p:
    if isAddress p then
      (if isAddress x then x == p
       else let d = domainOf p; in d == x || lib.hasSuffix ".${x}" d)
    else if isAddress x then addressHits x p
    else domainHits x p;

  # Identifiers can include list names, sender addresses and relay domains.
  listHits = x: p:
    if isAddress p then lib.hasInfix p x
    else lib.any (token: token == p || lib.hasSuffix ".${p}" token)
      (lib.filter builtins.isString (builtins.split "[^a-z0-9.-]+" x));
  violates = e:
    if e.kind == "list" then lib.any (listHits e.value) protected.strict
    else lib.any (hits e.value) protected.strict
      || (e.kind == "domain" && lib.any (domainHits e.value) protected.domainOnly);

  # Every consumer view derives from the checked list, so a protected sender
  # fails evaluation instead of reaching either trash producer.
  entries =
    let bad = lib.filter violates normalised; in
    if bad == [] then normalised
    else throw "taxonomy: trash entries match a protected domain: ${
      lib.concatMapStringsSep ", " (e: e.value) bad}";
  inScope = scope: lib.filter (e: e.scope == "both" || e.scope == scope) entries;

  protonChecked = inScope "proton";
in
{
  inherit data;

  derived = {
    # Gmail janitor wire: plain strings, unchanged shape. It does not classify
    # or place local mail.
    trashSenders = map (e: e.value) (inScope "gmail");

    # Proton Sieve view, split by match kind (aerc/parts/sieve-filters.nix).
    protonTrash = {
      domains   = map (e: e.value) (lib.filter (e: e.kind == "domain") protonChecked);
      addresses = map (e: e.value) (lib.filter (e: e.kind == "address") protonChecked);
      lists     = map (e: e.value) (lib.filter (e: e.kind == "list") protonChecked);
    };
  };
}
