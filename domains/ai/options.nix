# domains/ai/options.nix
#
# Top-level AI domain options
# Charter v7.0 compliant - single hwc.ai.* namespace
#
# NOTE: Individual service options (ollama, open-webui, etc.) are defined
# in their respective options.nix files within subdirectories.
#
{ lib, ... }:

{
  options.hwc.ai = {
    enable = lib.mkEnableOption "AI domain - top level enable";
  };
}
