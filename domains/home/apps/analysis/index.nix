# domains/home/apps/analysis/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  inherit (lib) mkIf mkMerge;
  cfg = config.hwc.home.apps.analysis;
  isNixOS = osConfig ? hwc;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.analysis = {
    enable = lib.mkEnableOption "Polars-based data analysis (JupyterLab)";

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional Python packages to include.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkIf cfg.enable {
    home.packages = with pkgs; let
      pythonEnv = python3.withPackages (ps: with ps; [
        polars
        jupyterlab
        # itables  # Not available in nixpkgs 25.05
        # hvplot   # Not available in nixpkgs 25.05
        pandas   # Optional compatibility
        numpy
        pyarrow
      ] ++ cfg.extraPackages);
    in [ pythonEnv ];

    # Assertions: use mkMerge to safely concatenate conditional lists
    assertions = mkMerge [
      [
        {
          assertion = pkgs ? python3;
          message = "Python 3 must be available in pkgs.";
        }
      ]
      (mkIf isNixOS [
        # Add NixOS-specific assertions here if needed
        # Example:
        # {
        #   assertion = true;  # or some real check
        #   message = "NixOS-specific check passed.";
        # }
      ])
    ];
  };
}
