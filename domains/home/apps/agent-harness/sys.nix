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

  # The GitHub server takes its token from gh's own login at launch, so the
  # generated file holds no credential.
  githubMcp = pkgs.writeShellScript "mcp-github" ''
    token=$(${pkgs.gh}/bin/gh auth token) || {
      echo "mcp-github: gh is not logged in on this host. Run: gh auth login" >&2
      exit 1
    }
    export GITHUB_PERSONAL_ACCESS_TOKEN=$token
    exec ${pkgs.nodejs}/bin/npx -y @modelcontextprotocol/server-github
  '';

  # The nixos repo's .mcp.json. It replaces the hand-kept .mcp.<host>.json
  # copies, which drifted: one ran a stale checkout build of the gateway, the
  # other had no gateway at all. hwc-sys is the Nix-built gateway service,
  # reached over its tailnet route, so every session on every host gets the
  # deployed code and the service's environment.
  projectMcpJson = pkgs.writeText "nixos-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        fetch = {
          command = "uvx";
          args = [ "mcp-server-fetch" ];
        };
        git = {
          command = "uvx";
          args = [
            "mcp-server-git"
            "--repository"
            cfg.projectMcp.repo
          ];
        };
        github.command = "${githubMcp}";
        memory = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-memory"
          ];
        };
        sequential-thinking = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-sequential-thinking"
          ];
        };
        time = {
          command = "uvx";
          args = [ "mcp-server-time" ];
        };
        hwc-sys = {
          type = "http";
          url = config.hwc.system.mcp.url;
        };
      }
      // cfg.projectMcp.extraServers;
    }
  );
in
{
  options.hwc.system.apps.agent-harness = {
    enable = lib.mkEnableOption "machine-wide agent harness policy";
    projectMcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Generate the nixos repo's .mcp.json (a symlink into the store).";
      };
      repo = lib.mkOption {
        type = lib.types.str;
        default = config.hwc.paths.nixos;
        defaultText = lib.literalExpression "config.hwc.paths.nixos";
        description = "Checkout whose .mcp.json is generated.";
      };
      extraServers = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Host-specific MCP servers added to the shared set (Claude Code .mcp.json entries).";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc."agent-harness".source = inputs.agent-harness;
    environment.etc."agent-harness-manifest.json".text = builtins.toJSON contract;
    environment.etc."claude-code/managed-settings.json".source = managedClaudeSettings;

    systemd.tmpfiles.rules = lib.mkIf cfg.projectMcp.enable [
      "L+ ${cfg.projectMcp.repo}/.mcp.json - - - - ${projectMcpJson}"
      # Temporary: the hand-kept per-host copies the generated file replaces
      # (2026-09-25). Remove these two lines once no fleet host has them:
      #   ssh <host> 'ls ~/.nixos/.mcp.laptop.json ~/.nixos/.mcp.server.json'
      "r ${cfg.projectMcp.repo}/.mcp.laptop.json"
      "r ${cfg.projectMcp.repo}/.mcp.server.json"
    ];
  };
}
