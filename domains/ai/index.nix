# domains/ai/index.nix
{ config, lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./mcp               # Model Context Protocol servers
    # tools/cloud/nanoclaw removed 2026-07-05 (never enabled — audit item 2.2);
    # agent/personas/profiles removed 2026-09-19 (local chat stack retired: no
    # consumer). Recover from git history if ever needed.
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
