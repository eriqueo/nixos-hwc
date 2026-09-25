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

  # Claude Code's MCP servers, generated so no host keeps a hand-edited copy.
  # The hand-kept files drifted: one ran a stale checkout build of the gateway,
  # one had no gateway, and every brain entry still named hwc-server after
  # brain-mcp moved to hwc-work. ~/.mcp.json applies to every project under the
  # home directory; the repo file adds what is specific to the nixos checkout.
  # hwc-sys is the Nix-built gateway service over its tailnet route, so every
  # session on every host gets the deployed code and the service's environment.
  userMcpJson = pkgs.writeText "user-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        fetch = {
          command = "uvx";
          args = [ "mcp-server-fetch" ];
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
        # Tailnet-gated, no token (brain-mcp dropped Bearer auth 2026-05-22).
        brain = {
          type = "http";
          url = cfg.userMcp.brainUrl;
        };
      };
    }
  );
  projectMcpJson = pkgs.writeText "nixos-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        git = {
          command = "uvx";
          args = [
            "mcp-server-git"
            "--repository"
            cfg.projectMcp.repo
          ];
        };
      }
      // cfg.projectMcp.extraServers;
    }
  );

  hosts = config.hwc.networking.hosts;
  # Alias of this host in the registry, when it has one (servers only).
  thisAlias = lib.findFirst (a: hosts.servers.${a} == config.networking.hostName) null (
    lib.attrNames hosts.servers
  );
  brainMcp = config.hwc.server.ai.brainMcp or { enable = false; };
in
{
  options.hwc.system.apps.agent-harness = {
    enable = lib.mkEnableOption "machine-wide agent harness policy";
    userMcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Generate ~/.mcp.json (a symlink into the store), read by every project under the home directory.";
      };
      brainUrl = lib.mkOption {
        type = lib.types.str;
        default = hosts.url {
          server = "work";
          port = 23443;
          path = "/mcp";
        };
        defaultText = lib.literalExpression ''hwc.networking.hosts.url { server = "work"; port = 23443; path = "/mcp"; }'';
        description = ''
          brain-mcp's tailnet endpoint. The host running brain-mcp asserts that
          this names its own route, so a move or port change fails the build.
        '';
      };
    };
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

    systemd.tmpfiles.rules =
      lib.optional cfg.userMcp.enable "L+ ${config.hwc.paths.user.home}/.mcp.json - - - - ${userMcpJson}"
      ++ lib.optionals cfg.projectMcp.enable [
        "L+ ${cfg.projectMcp.repo}/.mcp.json - - - - ${projectMcpJson}"
        # Temporary: the hand-kept per-host copies the generated file replaces
        # (2026-09-25). Remove these two lines once no fleet host has them:
        #   ssh <host> 'ls ~/.nixos/.mcp.laptop.json ~/.nixos/.mcp.server.json'
        "r ${cfg.projectMcp.repo}/.mcp.laptop.json"
        "r ${cfg.projectMcp.repo}/.mcp.server.json"
      ];

    assertions = [
      {
        # Checked where brain-mcp runs: the URL every host's sessions use must
        # be this host's own route.
        assertion =
          !(cfg.userMcp.enable && brainMcp.enable)
          || (
            thisAlias != null
            && cfg.userMcp.brainUrl == hosts.url {
              server = thisAlias;
              port = brainMcp.reverseProxyPort;
              path = "/mcp";
            }
          );
        message = "hwc.system.apps.agent-harness.userMcp.brainUrl (${cfg.userMcp.brainUrl}) does not name brain-mcp's route on ${config.networking.hostName}. Update its default when brain-mcp moves or changes port.";
      }
    ];
  };
}
