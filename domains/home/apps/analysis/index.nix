{ config, lib, pkgs, osConfig ? {}, ... }:

let
  inherit (lib) mkIf;

  cfg = config.hwc.home.apps.analysis;

  isNixOS = osConfig ? hwc;  # Clean boolean check (no 'or false' needed)
in {
  # OPTIONS (mandatory)
  imports = [ ./options.nix ];

  # IMPLEMENTATION + VALIDATION (merged into one config block)
  config = mkIf cfg.enable {
    home.packages = with pkgs; let
      pythonEnv = python3.withPackages (ps: with ps; [
        polars
        jupyterlab
        itables
        hvplot
        pandas   # Optional compatibility
        numpy
        pyarrow
      ] ++ cfg.extraPackages);
    in [ pythonEnv ];

    # Assertions go here inside the same config
    assertions = [
      {
        assertion = pkgs ? python3;
        message = "Python 3 must be available in pkgs.";
      }
    ] ++ lib.mkIf isNixOS [
      # Add any NixOS-specific assertions here (rarely needed for home modules)
    ];
  };
}
