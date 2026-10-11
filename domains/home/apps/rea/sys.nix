# domains/home/apps/rea/sys.nix — system lane (Charter Law 7)
#
# Registers REA's MCP server in Claude Code's user-level ~/.mcp.json, which
# agent-harness/sys.nix generates. The entry names the store path of the same
# pinned build the home lane installs, so a session gets REA's tools whether
# or not `rea` is on PATH, and never an `npx rea-agents@…` network fetch.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.apps.rea;
  reaPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./parts/package.nix { };
in
{
  options.hwc.system.apps.rea = {
    enable = lib.mkEnableOption "REA MCP server in Claude Code's user-level MCP config";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "REA package the MCP entry runs. Keep in step with hwc.home.apps.rea.package.";
    };
  };

  config = lib.mkIf cfg.enable {
    hwc.system.apps.agent-harness.userMcp.extraServers.rea = {
      command = "${reaPkg}/bin/rea";
      args = [ "mcp" ];
    };

    assertions = [
      {
        assertion = config.hwc.system.apps.agent-harness.enable && config.hwc.system.apps.agent-harness.userMcp.enable;
        message = "hwc.system.apps.rea.enable needs agent-harness userMcp: ~/.mcp.json is generated there.";
      }
    ];
  };
}
