{ config, pkgs, ... }:
{
  # Enable flakes and modern nix command features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Machine identification
  networking.hostName = "immich-worker";

  # Join Tailscale network for secure connectivity
  services.tailscale.enable = true;

  # Mount shared photo storage from main server via NFS
  fileSystems."/mnt/shared-photos" = {
    device = "hwc-server:/mnt/hot/pictures";
    fsType = "nfs";
    options = [ "rw" "vers=4" ];
  };

  # Configure Immich machine-learning service only
  systemd.services.immich-machine-learning = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.immich}/bin/immich-machine-learning";
      Environment = [
        "IMMICH_HOST=100.115.126.41"
        "DATABASE_URL=postgresql://immich_new@100.115.126.41:5432/immich_new"
        "REDIS_HOST=100.115.126.41"
        "REDIS_PORT=6381"
      ];
    };
  };
}
