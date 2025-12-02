# profiles/ai.nix
{ lib, ... }:
{
  imports = [
    ../domains/ai/default.nix
    # The domain modules (ollama, open-webui, local-workflows, mcp, agent)
    # will be imported inside domains/ai/default.nix
  ];

  # set high-level sensible defaults as mkDefault for downstream overrides
  hwc.ai = {
    ollama = {
      enable = lib.mkDefault true;
      models = lib.mkDefault [ "phi3.5:3.8b" "llama3.2:3b" ];
    };
    local-workflows = {
      enable = lib.mkDefault true;
      chatCli = {
        model = lib.mkDefault "phi3.5:3.8b";
        systemPrompt = lib.mkDefault ''
          Sysadmin assistant. Execute commands, explain clearly.

          WORKFLOW:
          1. Run TOOL: command immediately (no questions)
          2. Show output
          3. Analyze and explain in plain English

          BEHAVIOR:
          - Assume defaults for vague queries
          - Always explain what output means
          - Identify issues, normal operations, or "no problems found"
          - Be direct, no pleasantries

          EXAMPLE:
          "errors" -> TOOL: journalctl -p err -b | tail -20
          After EVERY command, provide 2-3 sentence human summary.
        '';
      };
    };
  };
}
