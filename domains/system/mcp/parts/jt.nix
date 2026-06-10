# domains/system/mcp/parts/jt.nix
#
# HWC JobTread MCP configuration — JT PAVE tools (63 JT PAVE tools)
#
# NOTE: JT is now a stdio backend of the unified gateway (hwc-sys-mcp).
# Options live in ../index.nix (parts/ must stay pure of mkOption per
# Charter v12). This file carries validation only. The standalone
# hwc-jt-mcp systemd service has been removed.
#
# NAMESPACE: hwc.system.mcp.jt.*
#
# DEPENDENCIES:
#   - agenix secrets: jobtread-grant-key (injected by gateway env service)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mcp.jt;
in
{
  #==========================================================================
  # IMPLEMENTATION — validation only (services managed by gateway)
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.age.secrets ? jobtread-grant-key;
        message = ''
          hwc.system.mcp.jt requires the jobtread-grant-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
