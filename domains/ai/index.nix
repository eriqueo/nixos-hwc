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
    ./local-workflows   # Automation workflows (file-cleanup, auto-doc, chat-cli)
    ./mcp               # Model Context Protocol servers
    ./cloud             # Cloud AI API integration
    ./agent             # HTTP tool agent
    ./nanoclaw          # NanoClaw AI agent orchestrator
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
