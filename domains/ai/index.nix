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
    ./open-webui        # Web UI for Ollama
    ./anything-llm      # Local AI assistant with file access
    ./local-workflows   # Automation workflows
    ./mcp               # Model Context Protocol servers
    ./cloud             # Cloud AI API integration
    ./router            # Local/cloud routing
    ./agent             # HTTP tool agent
    ./ai-bible/index.nix  # AI-powered documentation system
    ./nanoclaw          # NanoClaw AI agent orchestrator
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
