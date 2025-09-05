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
    # System target(s)
    system = "x86_64-linux";

    # Package set (kept here so behavior is unchanged; alternative is module-based nixpkgs.config)
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        home-manager.nixosModules.home-manager-overlay
      ];
    };

    lib = nixpkgs.lib;
  in {
    #---------------------------------------------------------------------------
    # NixOS Configurations
    #---------------------------------------------------------------------------
    nixosConfigurations = {
      hwc-server = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };  # pass inputs; no hardware/service logic here
        modules = [
          agenix.nixosModules.default
          ./machines/server/config.nix
          # (Home Manager optional on server; add if desired)
        ];
      };

      hwc-laptop = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };  # pass inputs; no hardware/service logic here
        modules = [
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager



          ./machines/laptop/config.nix

        ];
      };
    };

    #---------------------------------------------------------------------------
    # DISABLED: Non-standard flake outputs that may interfere with Home Manager
    #---------------------------------------------------------------------------
    # agenixConfig = import ./secrets.nix;
    # helpers = {
    #   inherit (import ./lib/helpers.nix { inherit lib; })
    #     mkServiceModule mkContainerService mkGpuService;
    #   migrationBridge = import ./lib/migration-bridge.nix { inherit inputs; };
    # };
  };
}
