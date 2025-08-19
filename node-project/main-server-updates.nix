{ config, pkgs, lib, ... }:
{
  # Enable NFS server for photo sharing
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/hot/pictures 100.115.126.0/24(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # Allow PostgreSQL access from Tailscale network
  services.postgresql = {
    authentication = ''
      host immich_new immich_new 100.115.126.0/24 trust
    '';
    settings.listen_addresses = "localhost,100.115.126.41";
  };

  # Redis bound to Tailscale interface
  services.redis.servers.immich = {
    bind = "100.115.126.41";
    settings.protected-mode = "no";
  };

  # Open necessary firewall ports on Tailscale interface
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    2049  # NFS
    5432  # PostgreSQL
    6381  # Redis
    2283  # Immich
  ];

  # Disable local machine-learning service
  systemd.services.immich-machine-learning.serviceConfig.ExecStart =
    lib.mkForce "/bin/true";
}
