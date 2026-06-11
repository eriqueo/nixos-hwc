# domains/home/apps/onlyoffice-desktopeditors/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "onlyoffice-desktopeditors";
  description = "OnlyOffice Desktop Editors";
  package = pkgs:
    pkgs.onlyoffice-desktopeditors.override {
      buildFHSEnv = args: pkgs.buildFHSEnv (args // {
        targetPkgs = pkgs': (args.targetPkgs pkgs') ++ [ pkgs'.libGL ];
        runScript = "/bin/onlyoffice-desktopeditors --force-scale=1.25";
      });
    };
}
