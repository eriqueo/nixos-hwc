# domains/networking/index.nix
#
# Networking domain — reverse proxy, VPN, DNS, podman network infrastructure.
# Provides the backbone that other domains depend on for service routing.
#
# Namespace: hwc.networking.{reverseProxy,gluetun,pihole}.*

{ lib, config, ... }:

{
  imports = [
    # Reverse proxy (Caddy NixOS service + route rendering)
    # Also declares hwc.networking.shared.{routes,tailscaleDomain,rootHost}
    ./reverseProxy.nix

    # NOTE: routes-lib.nix NOT imported — was dead code in _shared/lib.nix
    # The routes option is already declared in reverseProxy.nix.

    # Centralized route definitions (pushes all service routes)
    ./routes.nix

    # Podman media-network creation (systemd oneshot)
    ./podman-network.nix

    # VPN container (gluetun)
    ./gluetun/index.nix

    # DNS container (pihole)
    ./pihole/index.nix
  ];
}
