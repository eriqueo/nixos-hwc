# nixos-hwc/flake.nix
#
# Flake: HWC NixOS Configuration (Modular Architecture)
# Orchestrates systems; delegates implementation to modules/profiles.
# No hardware driver logic or service details here (Charter v3).
#
# DEPENDENCIES (Upstream):
#   - nixpkgs (nixos-unstable), nixpkgs-stable (24.05)
#   - home-manager (follows nixpkgs)
#   - agenix (follows nixpkgs)
#   - legacy-config (non-flake, for migration reference)
#
# USED BY (Downstream):
#   - nixosConfigurations.hwc-laptop -> ./machines/laptop/config.nix
#   - nixosConfigurations.hwc-server -> ./machines/server/config.nix
#
# IMPORTS REQUIRED IN:
#   - machines/*/config.nix import profiles/* and modules/*
#
# USAGE:
#   nixos-rebuild switch --flake .#hwc-laptop
#   nixos-rebuild switch --flake .#hwc-server

{
  #============================================================================
  # INPUTS - Pin sources
  #============================================================================
  description = "HWC NixOS Configuration - Modular Architecture";

  inputs = {
    nixpkgs.url         = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url  = "github:NixOS/nixpkgs/nixos-24.05";

    nixvirt = {
        url = "github:AshleyYakeley/NixVirt";
        inputs.nixpkgs.follows = "nixpkgs";
      };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Reference repo during migration (non-flake)
    legacy-config = {
      url = "github:eriqueo/nixos-hwc";
      flake = false;
    };
  };

  #============================================================================
  # OUTPUTS - Define systems; delegate implementation to machine configs
  #============================================================================

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, agenix, legacy-config, ... }@inputs:
  let
    system = "x86_64-linux";

    # Add the overlay here - this is the safest approach
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        # Accept NVIDIA license for legacy driver support
        nvidia.acceptLicense = true;
      };
      overlays = [];
    };
    
    lib = nixpkgs.lib;

    # Helper: hwc-graph package
    hwc-graph-pkg = pkgs.writeScriptBin "hwc-graph" ''
      #!${pkgs.python3}/bin/python3
      import sys
      import os

      # Add the graph directory to Python path
      graph_dir = "${self}/workspace/utilities/graph"
      sys.path.insert(0, graph_dir)

      # Change to repo root for scanning
      os.chdir("${self}")

      # Import and run main
      from hwc_graph import main
      main()
    '';

    # Audit tooling packages
    charter-lint = pkgs.writeScriptBin "charter-lint" ''
      #!${pkgs.bash}/bin/bash
      cd ${self}
      exec ${pkgs.bash}/bin/bash ${self}/scripts/audit/lint.sh "$@"
    '';

    charter-drift = pkgs.writeScriptBin "charter-drift" ''
      #!${pkgs.python3}/bin/python3
      import sys
      import os
      os.chdir("${self}")
      exec(open("${self}/scripts/audit/drift.py").read())
    '';

  in {
    # Apps - CLI utilities
    apps.${system} = {
      hwc-graph = {
        type = "app";
        program = "${hwc-graph-pkg}/bin/hwc-graph";
      };
      lint = {
        type = "app";
        program = "${charter-lint}/bin/charter-lint";
      };
      drift = {
        type = "app";
        program = "${charter-drift}/bin/charter-drift";
      };
    };

    # Packages - Make hwc-graph available as a package too
    packages.${system} = {
      hwc-graph = hwc-graph-pkg;
      charter-lint = charter-lint;
      charter-drift = charter-drift;
    };

    # Checks - CHARTER compliance gates
    checks.${system} = {
      charter-compliance = pkgs.runCommand "charter-compliance-check" {
        buildInputs = [ pkgs.bash pkgs.ripgrep ];
      } ''
        cd ${self}
        ${pkgs.bash}/bin/bash ${self}/scripts/audit/lint.sh ${self}
        touch $out
      '';
    };

    nixosConfigurations = {
      hwc-server = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          ./machines/server/config.nix
          {
            # Disable Home Manager on server - it's enabled somewhere in domains
            home-manager.users.eric.home.stateVersion = "24.05";
            home-manager.backupFileExtension = "backup";
            # Pass inputs to Home Manager modules
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
        ];
      };
      hwc-laptop = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          agenix.nixosModules.default
          inputs.nixvirt.nixosModules.default
          home-manager.nixosModules.home-manager
          ./machines/laptop/config.nix
        ];
      };
    };
  };
}
