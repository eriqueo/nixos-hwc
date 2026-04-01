# domains/system/index.nix — domain aggregator
{ ... }:
{
  imports = [
    ./core/index.nix           # packages, login, authentik
    ./gpu.nix                  # NVIDIA/AMD/Intel GPU acceleration
    ./hardware.nix             # audio, keyboard, bluetooth, monitoring
    ./networking.nix           # SSH, Tailscale, Samba, firewall
    ./mounts.nix               # storage tiers, USB auto-mount
    ./users.nix                # accounts, identity, SSH
  ];

  config = {};
}
