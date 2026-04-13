# domains/system/mcp/parts/jt.nix
#
# HWC JobTread MCP configuration — JT PAVE tools (63 JT PAVE tools)
#
# NOTE: JT is now a stdio backend of the unified gateway (hwc-sys-mcp).
# This file only declares options used by the gateway. The standalone
# hwc-jt-mcp systemd service has been removed.
#
# NAMESPACE: hwc.system.mcp.jt.*
#
# DEPENDENCIES:
#   - agenix secrets: jobtread-grant-key (injected by gateway env service)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mcp.jt;
  paths = config.hwc.paths;
in
{
  #==========================================================================
  # OPTIONS (consumed by gateway in index.nix)
  #==========================================================================
  options.hwc.system.mcp.jt = {
    enable = lib.mkEnableOption "HWC JobTread MCP tools — JT PAVE tools via gateway stdio backend";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6102;
      description = "Legacy option — no longer used (JT is a stdio backend). Kept for config compat.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Legacy option — no longer used (JT is a stdio backend).";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Server log level (passed to jt-mcp child process)";
    };

    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/jt-mcp";
      description = "Path to the built JT MCP server (contains dist/)";
    };

    # ── JobTread configuration ───────────────────────────────────────────
    jt = {
      orgId = lib.mkOption {
        type = lib.types.str;
        default = "22Nm3uFevXMb";
        description = "JobTread organization ID";
      };

      userId = lib.mkOption {
        type = lib.types.str;
        default = "22Nm3uFeRB7s";
        description = "JobTread user ID";
      };

      apiUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://api.jobtread.com/pave";
        description = "JobTread PAVE API endpoint";
      };
    };
  };

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
