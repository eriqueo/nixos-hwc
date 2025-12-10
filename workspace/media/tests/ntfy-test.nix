{ nixpkgs }:
let
  nixosTest = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../domains/system/paths.nix
      ../domains/server/ntfy.nix
      {
        hwc.services.ntfy.enable = true;
        
        # Minimal config for testing
        boot.loader.grub.device = "nodev";
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
      }
    ];
  };
in
  nixosTest.config.system.build.toplevel
