# domains/gaming/index.nix
#
# Gaming Domain - Emulation and game streaming services
#
# NAMESPACE: hwc.gaming.{retroarch,webdav}.*
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
