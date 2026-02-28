# domains/server/native/networking/options.nix
#
# DEPRECATED: Most networking functionality has been migrated:
#   - VPN/Gluetun: hwc.server.containers.gluetun
#   - Tailscale: hwc.system.networking.tailscale
#   - YouTube APIs: hwc.server.native.youtube.*
#
# This file remains for potential future server-specific networking options.

{ lib, config, ... }:

{
  # Empty options - all functionality moved to proper domains
}
