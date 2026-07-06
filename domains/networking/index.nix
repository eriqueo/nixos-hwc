# domains/networking/index.nix
#
# Networking domain — reverse proxy, VPN, DNS, podman network infrastructure.
# Provides the backbone that other domains depend on for service routing.
#
# Namespace: hwc.networking.{hosts,reverseProxy,gluetun,vpn}.*

{ lib, config, ... }:

{
  imports = [
    # Host registry — single source of truth for tailnet identities.
    # Declares hwc.networking.hosts.{tailnetSuffix,servers,primary,fqdn,url}.
    ./hosts/index.nix

    # Reverse proxy (Caddy NixOS service + route rendering)
    # Also declares hwc.networking.shared.{routes,tailscaleDomain,rootHost}
    ./reverseProxy/index.nix

    # NOTE: routes-lib.nix NOT imported — was dead code in _shared/lib.nix
    # The routes option is already declared in reverseProxy.nix.

    # Centralized route definitions (pushes all service routes)
    ./routes.nix

    # Podman media-network creation (systemd oneshot)
    ./podman-network.nix

    # VPN container (gluetun)
    ./gluetun/index.nix

    # ProtonVPN CLI service — MOVED from domains/system/services/vpn
    ./vpn/index.nix

    # Cloudflare Tunnel — public webhook ingress (webhooks.heartwoodcraft.me)
    ./cloudflared/index.nix
  ];
}
