# domains/ai/index.nix
{ config, lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./profiles          # Hardware profile detection and defaults
    ./tools             # AI CLI tools (charter-search, ai-doc, ai-commit, etc.)
    ./ollama            # Local LLM service
    ./mcp               # Model Context Protocol servers
    ./cloud             # Cloud AI API integration
    ./agent             # HTTP tool agent
    ./personas          # `hwc-llm` persona CLI for local llama.cpp services
    # ./nanoclaw — disabled 2026-05-29; superseded by hwc.server.ai.hermes
    # (Hermes Agent is the upstream successor to OpenClaw/NanoClaw).
    # Module moved to .nanoclaw-disabled/. Remove fully in a later cleanup pass.
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
