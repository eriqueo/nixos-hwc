{
  description = "HWC NixOS Configuration - Modular Architecture";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Reference to your current config during migration
    legacy-config = {
      url = "github:eriqueo/nixos-hwc";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, sops-nix, legacy-config, ... }@inputs:
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
          ./machines/hwc-server.nix
          sops-nix.nixosModules.sops
        ];
      };

      hwc-laptop = lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit inputs; };
        modules = [
          ./machines/laptop/config.nix
          home-manager.nixosModules.home-manager
        ];
      };
    };

    # Helper functions for migration
    lib = {
      inherit (import ./lib/helpers.nix { inherit lib; })
        mkServiceModule mkContainerService mkGpuService;
      migrationBridge = import ./lib/migration-bridge.nix { inherit inputs; };
    };
  };
}
