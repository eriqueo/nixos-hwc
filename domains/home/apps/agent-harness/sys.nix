{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hwc.system.apps.agent-harness;
  revision = inputs.agent-harness.rev or "dirty";
  contract = import ./contract.nix { inherit revision; };
  managedClaudeSettings =
    pkgs.runCommand "claude-managed-settings.json" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq '
          .hooks.UserPromptSubmit[]?.hooks |= map(select((.command | contains("standing-instructions.sh")) | not))
          | walk(if type == "string" then
              gsub("/home/eric/.claude-config"; "/etc/agent-harness")
              | gsub("/home/eric/.claude/hooks/principles"; "/etc/agent-harness/hooks/principles")
            else . end)
        ' ${inputs.agent-harness}/settings.json > "$out"
      '';
in
{
  options.hwc.system.apps.agent-harness.enable =
    lib.mkEnableOption "machine-wide agent harness policy";
  config = lib.mkIf cfg.enable {
    environment.etc."agent-harness".source = inputs.agent-harness;
    environment.etc."agent-harness-manifest.json".text = builtins.toJSON contract;
    environment.etc."claude-code/managed-settings.json".source = managedClaudeSettings;
  };
}
