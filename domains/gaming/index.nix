# domains/gaming/index.nix
#
# Gaming Domain - Emulation and game streaming services
#
# NAMESPACE: hwc.server.native.retroarch.*, hwc.server.native.webdav.*
#   (namespace migration deferred to later phase)
#
# USED BY:
#   - machines/server/config.nix

{ lib, config, ... }:

{
  imports = [
    ./retroarch/index.nix
    ./webdav/index.nix
  ];
}
