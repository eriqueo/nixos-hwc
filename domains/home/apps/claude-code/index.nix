{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
in
{
  options.hwc.home.apps.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI";

    installMethod = lib.mkOption {
      type = lib.types.enum [ "nix" "native" ];
      default = "nix";
      description = "Nix installs the channel package; native uses the existing self-updating CLI in ~/.local/bin.";
    };

    obsidianCert.enable = lib.mkEnableOption "trust for the local Obsidian REST API certificate";

  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.installMethod == "nix") pkgs.claude-code;
    home.sessionPath = lib.optional (cfg.installMethod == "native") "${config.home.homeDirectory}/.local/bin";

    # Trust the local Obsidian REST API's self-signed certificate.
    home.sessionVariables = lib.mkIf cfg.obsidianCert.enable {
      NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.claude/certs/obsidian-local-rest-api.crt";
    };
  };
}
