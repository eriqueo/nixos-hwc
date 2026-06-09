# domains/secrets/lib.nix
#
# Pure, lib-free generator core for the agenix secrets system.
#
# Single source of truth: the directory tree of `.age` files under
# domains/secrets/parts/. This file walks that tree and emits BOTH:
#   - recipient rules for secrets.nix  (mkRecipients, path-keyed)
#   - age.secrets mounts               (mkMounts, name-keyed)
#
# It is imported from TWO contexts:
#   1. secrets.nix — evaluated standalone by the agenix CLI, with NO `lib`
#      in scope. Hence this core uses `builtins` only.
#   2. declarations/generated.nix — a normal NixOS module.
#
# Name derivation (reproduces the historical hand-written names byte-exact):
#   path under category dir  ->  subdir segments prefixed, joined by "-",
#   base name truncated at the first ".", underscores rewritten to "-".
#     jellyfin/admin-password.age   -> jellyfin-admin-password
#     scraper/facebook-email.age    -> scraper-facebook-email
#     gemini_api_key.age            -> gemini-api-key
#     gmail-oauth-client.json.age   -> gmail-oauth-client
#
# The `caddy/` subtree is excluded: those certs are mounted with runtime
# hostname selection by domains/secrets/parts/caddy.nix and must stay
# hand-written.
{ }:
let
  inherit (builtins)
    readDir attrNames concatMap elemAt genList length listToAttrs
    concatStringsSep replaceStrings split filter isString match head;

  # "a/b/c" -> [ "a" "b" "c" ]  (builtins.split interleaves match groups; drop them)
  splitSlash = s: filter isString (split "/" s);

  # "admin-password.json.age" -> "admin-password"  (everything before the first dot)
  stripExt = s: head (split "\\." s);

  isAge = n: match ".*\\.age" n != null;

  last = xs: elemAt xs (length xs - 1);
  init = xs: genList (i: elemAt xs i) (length xs - 1);

  # relUnderCat: path beneath the category dir, e.g. "jellyfin/admin-password.age"
  deriveName = relUnderCat:
    let
      segs   = splitSlash relUnderCat;
      bare   = stripExt (last segs);
      prefix = init segs;
    in replaceStrings [ "_" ] [ "-" ] (concatStringsSep "-" (prefix ++ [ bare ]));

  # Recursively collect every *.age under partsDir, excluding the caddy/ subtree.
  # Returns [ { rel; category; relUnderCat; name; } ] where `rel` is the path
  # relative to partsDir (e.g. "services/jellyfin/admin-password.age").
  walkParts = partsDir:
    let
      go = subpath:
        let
          here   = if subpath == "" then partsDir else partsDir + ("/" + subpath);
          dirent = readDir here;
        in concatMap (n:
             let
               kind = dirent.${n};
               rel  = if subpath == "" then n else "${subpath}/${n}";
             in
               if kind == "directory" then
                 (if subpath == "" && n == "caddy" then [ ] else go rel)
               else if kind == "regular" && isAge n then
                 let
                   segs        = splitSlash rel;            # [ category, ...subdirs, file.age ]
                   relUnderCat = concatStringsSep "/"        # drop the leading category segment
                     (genList (i: elemAt segs (i + 1)) (length segs - 1));
                 in [ {
                   inherit rel;
                   name = deriveName relUnderCat;
                 } ]
               else [ ]
           ) (attrNames dirent);
    in go "";

in {
  inherit deriveName walkParts;

  # ── recipients (for secrets.nix) ────────────────────────────────────────────
  #   partsDir        : path literal to domains/secrets/parts
  #   partsPrefix     : string prefix for the rule key, e.g. "domains/secrets/parts"
  #   everyone        : the default recipient list (all hosts + eric)
  #   recipientOverrides : name -> publicKeys list (empty in normal operation)
  #   caddyRecipients : hand-written attrset of the caddy rules (merged in last)
  mkRecipients = { partsDir, partsPrefix, everyone, recipientOverrides ? { }, caddyRecipients ? { } }:
    let
      entries = walkParts partsDir;
      ruleFor = e: {
        name  = "${partsPrefix}/${e.rel}";
        value = {
          publicKeys =
            if recipientOverrides ? ${e.name} then recipientOverrides.${e.name} else everyone;
        };
      };
    in (listToAttrs (map ruleFor entries)) // caddyRecipients;

  # ── mounts (for declarations/generated.nix) ─────────────────────────────────
  #   fileFor        : rel -> the agenix `file` path (caller supplies; Nix path
  #                    literals resolve relative to the calling file)
  #   defaultMount   : { mode; owner; group; } applied to every secret
  #   mountOverrides : name -> partial attrset merged over the default
  mkMounts = { partsDir, fileFor, defaultMount, mountOverrides ? { } }:
    let
      entries  = walkParts partsDir;
      mountFor = e: {
        name  = e.name;
        value = (defaultMount // { file = fileFor e.rel; })
                // (mountOverrides.${e.name} or { });
      };
    in listToAttrs (map mountFor entries);
}
