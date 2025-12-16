# domains/server/ai/ai-bible/index.nix
#
# AI Bible subdomain aggregator
# Imports options and AI Bible implementation

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/ai-bible.nix
  ];
}