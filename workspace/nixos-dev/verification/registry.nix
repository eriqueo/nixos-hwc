{ lib, repoRoot, groups }:
let
  names = lib.concatMap builtins.attrNames groups;
  entries = lib.foldl' (a: b: a // b) {} groups;
  valid = entry:
    entry ? derivation && entry ? owner && entry ? kind
    && builtins.pathExists (repoRoot + "/${entry.owner}")
    && lib.elem entry.kind [ "governance" "shared" "integration" "compatibility" ]
    && (entry.kind != "compatibility" || (entry ? retirement && entry.retirement != ""));
in
assert lib.assertMsg (builtins.length names == builtins.length (lib.unique names)) "Duplicate verification check name";
assert lib.assertMsg (lib.all valid (builtins.attrValues entries)) "Invalid verification owner, kind or retirement condition";
entries
