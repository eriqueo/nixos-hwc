{ nixpkgs }:
let
  nixosTest = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../modules/system/paths.nix
      ../modules/server/ntfy.nix
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
