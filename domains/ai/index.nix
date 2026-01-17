# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./profiles          # Hardware profile detection and defaults
    ./tools             # AI CLI tools (charter-search, ai-doc, ai-commit, etc.)
    ./ollama            # Local LLM service
    ./open-webui        # Web UI for Ollama
    ./local-workflows   # Automation workflows
    ./mcp               # Model Context Protocol servers
    ./cloud             # Cloud AI API integration
    ./router            # Local/cloud routing
    ./agent             # HTTP tool agent
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };

}
