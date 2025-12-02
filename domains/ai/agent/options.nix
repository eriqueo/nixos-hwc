{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.ai.agent = {
    enable = mkEnableOption "AI Agent - HTTP tool agent";
    port = mkOption {
      type = types.port;
      default = 6020;
    };
    allowedCommands = mkOption {
      type = types.listOf types.str;
      default = [ "podman ps" "podman logs" "systemctl status" "journalctl -n 200" "ls" "cat" ];
    };
    auditLog = mkOption {
      type = types.path;
      default = "/var/log/hwc-ai/agent-audit.log";
    };
  };
}
