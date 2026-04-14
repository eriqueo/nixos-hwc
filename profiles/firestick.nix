{ lib, ... }:

{
  # Lean travel-TV stack: reuse core profile defaults, then strip extras.
  imports = [
    ./core.nix
  ];

  # No backups or Samba on the stick.
  hwc.data.backup.enable = lib.mkForce false;
  hwc.system.networking.samba.enable = lib.mkForce false;

  # Keep audio, trim monitoring/key remapping to stay lightweight.
  hwc.system.hardware = {
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
