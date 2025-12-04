# domains/ai/options.nix
#
# Top-level AI domain options
# Charter v7.0 compliant - single hwc.ai.* namespace
#
# NOTE: Individual service options (Ollama, open-webui, etc.) are defined
# in their respective options.nix files in the subdirectories. This file
# declares the top-level container for ai options and adds the agent/router
# sub-option trees so machines can safely set hwc.ai.agent.* and hwc.ai.router.*.
#
{ lib, ... }:

{
  options.hwc.ai = {
    enable = lib.mkEnableOption "AI domain - top level enable";

    # Agent options are defined in domains/ai/agent/options.nix
    # Router options are defined in domains/ai/router/options.nix (Sprint 4.4)
    # Cloud options are defined in domains/ai/cloud/options.nix (Sprint 4.3)
  };
}
