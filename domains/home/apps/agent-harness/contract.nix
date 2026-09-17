{ revision }:
{
  schemaVersion = 1;

  staticPolicy = {
    owner = "nix-input:agent-harness";
    inherit revision;
    authoringRepo = "~/.claude-config";
    runtimeRoot = "/etc/agent-harness";
    publishCommand = "agent-harness publish";
  };

  mutableState = {
    owner = "agent-state";
    runtimeRoot = "~/.agent-state";
    syncCommand = "agent-harness sync";
    allowedRoots = [
      "MISTAKES.md"
      ".mistakes-dismissed.log"
      "projects/*/memory"
    ];
  };

  projectPolicy = {
    owner = "project-repository";
    roots = [
      "AGENTS.md"
      "CLAUDE.md"
    ];
  };

  providers = {
    claude = {
      policyOwner = "nix";
      stateOwner = "agent-state";
    };
    codex = {
      policyOwner = "nix";
      stateOwner = "agent-state";
    };
    pi = {
      policyOwner = "nix";
      stateOwner = "agent-state";
      model = "dx2/llm";
    };
    t3 = {
      policyOwner = "nix";
      role = "launcher";
    };
    herdr = {
      policyOwner = "nix";
      role = "status-integration";
    };
  };

  invariants = [
    "runtime-static-policy-never-references-authoring-repo"
    "system-and-user-policy-revisions-match"
    "mutable-state-never-contains-static-policy"
    "new-or-changed-memory-declares-authority-and-source"
    "one-owner-per-provider-integration"
  ];
}
