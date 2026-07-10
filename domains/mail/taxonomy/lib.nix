# domains/mail/taxonomy/lib.nix
#
# Pure derivation helpers over data.nix — per-consumer views of the canonical
# taxonomy. Importable from both lanes (`import .../taxonomy/lib.nix { inherit lib; }`).
# No options, no pkgs; callers bake artifacts themselves (e.g. pkgs.writeText
# on jsonText).
{ lib }:
let
  data = import ./data.nix;
  s = data.senders;

  matchOf = e: if builtins.isString e then e else e.match;
  bullet = e:
    if builtins.isString e
    then "- ${e}"
    else "- ${e.match}" + (lib.optionalString (e ? note) " (${e.note})");

  # Safe merge direction: senders the rules already trash/archive are by
  # definition LLM-noise. Emit them after the curated noise entries, minus
  # any match the noise list already carries.
  noiseMatches = map matchOf s.noise;
  ruleFedExtras = lib.filter (m: !(lib.elem m noiseMatches))
    (lib.unique (s.trash ++ s.archive));

  noiseBullets = (map bullet s.noise) ++ (map (m: "- ${m}") ruleFedExtras);
  reviewBullets = map bullet s.review;
in
{
  inherit data;

  # Per-disposition lists for the notmuch rule options (rules.nix consumers).
  derived = {
    trashSenders = s.trash;
    archiveSenders = s.archive;
    newsletterSenders = s.newsletter;
    notificationSenders = s.notification;
    financeSenders = s.finance;
    actionSubjects = data.actionSubjects;
  };

  # mail-taxonomy.json for the MCP gateway (HWC_MAIL_TAXONOMY_FILE).
  # Names only — display/colors are presentation and stay in aerc.
  jsonText = builtins.toJSON {
    version = 1;
    triage = data.triage;
    categories = map (c: c.tag) data.categories;
    flags = map (f: f.tag) data.flags;
    # Flags that bulk clear operations must never remove (e.g. `keep`).
    protectedFlags = map (f: f.tag) (lib.filter (f: f.protected or false) data.flags);
  };

  # "Known senders" section of the mail-triage prompt (replaces the
  # hand-kept lists that used to live in prompts/mail-triage.txt).
  promptFragment = ''
    Known noise senders (always assign to noise bucket, suggested_action: trash):
    ${lib.concatStringsSep "\n" noiseBullets}

    Known review senders (always assign to review):
    ${lib.concatStringsSep "\n" reviewBullets}'';
}
