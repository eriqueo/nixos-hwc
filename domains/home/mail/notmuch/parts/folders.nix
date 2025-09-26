{ lib, config }:
let
  common = import ../../parts/common.nix { inherit lib; };
  accs = lib.attrValues (config.hwc.home.mail.accounts or {});
  orJoin = xs: lib.concatStringsSep " OR " xs;

  folders = a: common.rolesFor a;

  sentClauses    = lib.flatten (map (a: map (f: ''folder:"${f}"'') (folders a).sent)    accs);
  draftsClauses  = lib.flatten (map (a: map (f: ''folder:"${f}"'') (folders a).drafts)  accs);
  trashClauses   = lib.flatten (map (a: map (f: ''folder:"${f}"'') (folders a).trash)   accs);
  spamClauses    = lib.flatten (map (a: map (f: ''folder:"${f}"'') (folders a).spam)    accs);
  archiveClauses = lib.flatten (map (a: map (f: ''folder:"${f}"'') (folders a).archive) accs);

  sent    = if sentClauses    == [] then "" else orJoin sentClauses;
  drafts  = if draftsClauses  == [] then "" else orJoin draftsClauses;
  trash   = if trashClauses   == [] then "" else orJoin trashClauses;
  spam    = if spamClauses    == [] then "" else orJoin spamClauses;
  archive = if archiveClauses == [] then "" else orJoin archiveClauses;
in
{ inherit sent drafts trash spam archive; }
