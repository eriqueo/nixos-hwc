{ lib, pkgs, config, ... }:
let
  userFilters = (config.hwc.home.apps.aerc.sieve.filters or {});

  defaultFilters = {
    "10-split-by-recipient.sieve" = ''
      require ["fileinto", "envelope"];
      if anyof(
        address :all :matches ["To","Cc","Bcc"] ["*@iheartwoodcraft.com"],
        envelope :all :matches "to" ["*@iheartwoodcraft.com"]
      ) {
        fileinto "HWC/INBOX";
        stop;
      }
      elsif anyof(
        address :all :is ["To","Cc","Bcc"] ["eriqueo@proton.me"],
        envelope :all :is "to" ["eriqueo@proton.me"]
      ) {
        fileinto "PROTON/INBOX";
        stop;
      }
    '';
  };

  filters = defaultFilters // userFilters;

  namesSorted = lib.sort (a: b: a < b) (builtins.attrNames filters);
  bundle = lib.concatStringsSep "\n\n"
    (map (n: "# ---- ${n}\n\n${filters.${n}}") namesSorted);

  sieveDir = ".config/aerc/sieve";
in {
  files = profileBase:
    (lib.mapAttrs'
      (name: text: { name = "${sieveDir}/filters/${name}"; value.text = text; })
      filters)
    // {
      "${sieveDir}/filters/bundle.sieve".text = bundle;
      "${sieveDir}/README".text = ''
        Managed by Home Manager.
        - Add Sieve via hwc.home.apps.aerc.sieve.filters.<name> = ''…'' in Nix.
        - Combined bundle: ${config.home.homeDirectory}/${sieveDir}/filters/bundle.sieve
        - Paste bundle into Proton > Filters > Add sieve filter (Sieve editor).
      '';
    };
}