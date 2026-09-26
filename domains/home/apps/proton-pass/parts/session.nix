# ProtonPass • Session part
# Session-scoped package only. Proton Pass owns its writable app settings.
{ lib, pkgs, config, osConfig ? {}, ... }:

{
  packages = [ pkgs.proton-pass ];
}
