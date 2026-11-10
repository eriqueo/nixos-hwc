{ lib, pkgs, self }:
let
  python = pkgs.python3.withPackages (ps: [ ps.tree-sitter ps.tree-sitter-grammars.tree-sitter-nix ]);
  registry = groups: import ./registry.nix { inherit lib groups; repoRoot = ../../..; };
  entry = { owner = "workspace/nixos-dev"; kind = "shared"; derivation = null; };
  rejects = groups: !(builtins.tryEval (builtins.deepSeq (registry groups) true)).success;
in
lib.genAttrs (map (law: "charter-law${toString law}") [ 1 2 4 5 7 10 12 14 16 ])
  (name: pkgs.runCommand name { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./charter.py} --root ${self} --law ${lib.removePrefix "charter-law" name}
    touch "$out"
  '')
// {
  verification-contract = pkgs.runCommand "verification-contract" { nativeBuildInputs = [ python pkgs.git pkgs.ripgrep ]; } ''
    cp ${./charter.py} charter.py
    cp ${./layout.py} layout.py
    cp ${./test_charter.py} test_charter.py
    cp ${./test_layout.py} test_layout.py
    cp ${./release.py} release.py
    cp ${./test_release.py} test_release.py
    export HWC_PERMISSION_LINTER=${self}/workspace/nixos-dev/lints/permission-lint.sh
    export HWC_README_GENERATOR=${self}/workspace/nixos-dev/generate-domain-readmes.py
    python3 -m unittest test_charter test_layout test_release
    touch "$out"
  '';
  verification-layout = pkgs.runCommand "verification-layout" { nativeBuildInputs = [ python ]; } ''
    python3 ${./layout.py} ${self}
    touch "$out"
  '';
  verification-registry =
    assert rejects [ { repeated = entry; } { repeated = entry; } ];
    assert rejects [ { missingOwner = entry // { owner = "does-not-exist"; }; } ];
    assert rejects [ { badKind = entry // { kind = "unknown"; }; } ];
    assert rejects [ { noRetirement = entry // { kind = "compatibility"; }; } ];
    assert builtins.attrNames (registry [ { valid = entry; } ]) == [ "valid" ];
    pkgs.runCommand "verification-registry" {} ''touch "$out"'';
}
