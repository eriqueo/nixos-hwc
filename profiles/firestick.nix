{ lib, ... }:

{
  # Lean travel-TV stack: reuse system profile defaults, then strip extras.
  imports = [
    ./system.nix
    ./security.nix
  ];

  # No backups or Samba on the stick.
  hwc.system.services.backup.enable = lib.mkForce false;
  hwc.system.networking.samba.enable = lib.mkForce false;

  # Keep audio, trim monitoring/key remapping to stay lightweight.
  hwc.system.services.hardware = {
    monitoring.enable = lib.mkForce false;
    keyboard.enable = lib.mkForce false;
  };

  # Networking tuned for quick boot and Tailscale-only access.
  hwc.system.networking = {
    waitOnline.mode = "off";
    firewall.level = lib.mkForce "basic";
    tailscale = {
      enable = true;
      extraUpFlags = [ "--ssh" ];
    };
    ssh.enable = true;
  };
}
