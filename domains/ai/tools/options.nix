# domains/ai/tools/options.nix
#
# AI CLI tools configuration options

{ lib, config, ... }:

{
  options.hwc.ai.tools = {
    enable = lib.mkEnableOption "AI CLI tools";

    charter = {
      charterPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.hwc.paths.nixos}/CHARTER.md";
        description = "Path to CHARTER.md file";
      };
    };

    logging = {
      enable = lib.mkEnableOption "AI tool logging";

      logDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.hwc.paths.user.home}/.local/share/ai-logs";
        description = "Directory for AI tool logs";
      };
    };
  };
}
