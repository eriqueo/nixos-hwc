# domains/system/index.nix — domain aggregator
{ ... }:
{
  imports = [
    ./core/index.nix           # packages, login, authentik
    ./gpu/index.nix            # NVIDIA/AMD/Intel GPU acceleration
    ./hardware/index.nix       # audio, keyboard, bluetooth, monitoring
    ./networking/index.nix     # SSH, Tailscale, Samba, firewall
    ./mounts/index.nix         # storage tiers
    ./usb-automount/index.nix  # USB drive auto-mount + NTFS fixperms
    ./users/index.nix          # accounts, identity, SSH
    ./mcp/index.nix            # Infrastructure MCP server
  ];

  config = {};
}
