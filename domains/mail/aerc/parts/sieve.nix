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
        "02 - Routing"). Change the taxonomy, run hms, then paste the changed
        file over its filter in Proton > Settings > Filters.
      '';
    };
}
