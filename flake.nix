{
  description = "HWC NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations = {
        hwc-server = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./machines/server.nix ];
        };
        hwc-laptop = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./machines/laptop.nix ];
        };
      };
    };
}
