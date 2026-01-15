{ config, lib, pkgs, osConfig ? {}, ... }:

let
  inherit (lib) mkIf;

  cfg = config.hwc.home.apps.analysis;

  isNixOS = osConfig ? hwc;
in {
  # OPTIONS (mandatory)
  imports = [ ./options.nix ];

  # IMPLEMENTATION (mandatory)
  config = mkIf cfg.enable {
    home.packages = with pkgs; let
      pythonEnv = python3.withPackages (ps: with ps; [
        polars
        jupyterlab
        itables
        hvplot
        pandas  # For compatibility if needed
        numpy
        pyarrow
      ] ++ cfg.extraPackages);
    in [ pythonEnv ];
  };

  # VALIDATION (mandatory when dependencies exist)
  config.assertions = mkIf cfg.enable [
    {
      assertion = pkgs ? python3;
      message = "Python 3 must be available in pkgs.";
    }
  ] ++ lib.mkIf isNixOS [
    # Add any NixOS-specific assertions here, e.g., for system deps
  ];
}
