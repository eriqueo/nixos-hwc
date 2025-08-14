{
  description = "HWC NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs, ... }@inputs: let
    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      hwc-server = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./machines/hwc-server.nix ];
      };
      hwc-laptop = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./machines/hwc-laptop.nix ];
      };
    };
  };
}
