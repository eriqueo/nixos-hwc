{
  description = "HWC NixOS Configuration - Modular Architecture";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Reference to your current config during migration
    legacy-config = {
      url = "github:eriqueo/nixos-hwc";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, agenix, legacy-config, ... }@inputs:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      hwc-server = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          ./machines/server/config.nix
          agenix.nixosModules.default
        ];
      };

      hwc-laptop = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          ./machines/laptop/config.nix
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
        ];
      };
    };

    # Agenix secrets configuration  
    agenixConfig = import ./secrets.nix;

    # Helper functions for migration
    lib = {
      inherit (import ./lib/helpers.nix { inherit lib; })
        mkServiceModule mkContainerService mkGpuService;
      migrationBridge = import ./lib/migration-bridge.nix { inherit inputs; };
    };
  };
}
