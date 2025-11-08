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

    fabric = {
      url = "github:danielmiessler/fabric";
      # Pin Fabric to use its own locked nixpkgs (c11863f1, April 2024)
      # which still has darwin.apple_sdk_11_0 needed by gomod2nix
      inputs.nixpkgs.url = "github:nixos/nixpkgs/c11863f1e964833214b767f4a369c6e6a7aba141";
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

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, agenix, fabric, legacy-config, ... }@inputs:
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
      overlays = [
        # Overlay to disable Tailscale tests
        (final: prev: {
          tailscale = prev.tailscale.overrideAttrs (oldAttrs: {
            doCheck = false;
          });
        })
      ];
    };
    
    lib = nixpkgs.lib;
  in {
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
