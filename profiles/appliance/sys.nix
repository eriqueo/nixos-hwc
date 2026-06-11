# profiles/appliance/sys.nix — appliance role, NixOS lane
#
# Lean travel-TV stack: strip extras from the base role defaults.
# Base role is supplied by the machine's role list — this role does NOT
# import it (roles never import roles).
#
# REPLACES: profiles/firestick.nix
# USED BY: firestick (role list in flake.nix machines table)

{ lib, ... }:

{
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
