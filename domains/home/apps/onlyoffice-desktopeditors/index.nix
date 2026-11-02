# domains/home/apps/onlyoffice-desktopeditors/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "onlyoffice-desktopeditors";
  description = "OnlyOffice Desktop Editors";
  package = pkgs:
    pkgs.onlyoffice-desktopeditors.override {
      # TEMPORARY: upstream still adds retired GTK2 to autoPatchelf inputs.
      # Strict ELF dependency checks must prove the GTK3/Qt build needs no GTK2.
      # Remove this once the upstream recipe drops that unused input.
      stdenv = pkgs.stdenv // {
        mkDerivation = attrs:
          assert attrs.pname == "onlyoffice-desktopeditors";
          pkgs.stdenv.mkDerivation (attrs // {
            buildInputs = builtins.filter (p:
              !((p.pname or "") == "gtk+" && pkgs.lib.versions.major (p.version or "0") == "2")
            ) attrs.buildInputs;
          });
      };
      buildFHSEnv = args: pkgs.buildFHSEnv (args // {
        targetPkgs = pkgs': (args.targetPkgs pkgs') ++ [ pkgs'.libGL ];
        runScript = "/bin/onlyoffice-desktopeditors --force-scale=1.25";
      });
    };
}
