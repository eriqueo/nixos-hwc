{ lib, ... }:
let
  filters = import ./sieve-filters.nix { inherit lib; };
  sieveDir = ".config/aerc/sieve";
in {
  files = _profileBase:
    lib.mapAttrs' (name: text: lib.nameValuePair "${sieveDir}/${name}" { inherit text; }) filters
    // {
      "${sieveDir}/README".text = ''
        Managed by Home Manager (domains/mail/aerc/parts/sieve-filters.nix).
        Each *.sieve file is one Proton filter, in name order ("01 - Junk",
        "02 - Routing"). Taxonomy changes can also change the Gmail janitor:
        commit and use nixos-rebuild switch for mixed changes. Paste each file
        into Proton > Settings > Filters after reviewing the active-mail audit.
        Disable the eight old filters for one day before deleting them.
      '';
    };
}
