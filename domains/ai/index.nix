# domains/ai/index.nix
{ config, lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./profiles          # Hardware profile detection and defaults
    ./mcp               # Model Context Protocol servers
    ./agent             # HTTP tool agent
    ./personas          # `hwc-llm` persona CLI for local llama.cpp services
    # tools/cloud/nanoclaw removed 2026-07-05 (never enabled — audit item 2.2);
    # recover from git history if ever needed.
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
