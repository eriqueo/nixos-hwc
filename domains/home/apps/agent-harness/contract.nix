# `manifest` is the harness manifest.toml, parsed.
{ revision, manifest }:
{
  schemaVersion = 1;

  staticPolicy = {
    owner = "nix-input:agent-harness";
    inherit revision;
    authoringRepo = "~/800_agents/harness";
    runtimeRoot = "/etc/agent-harness";
    publishCommand = "agent-harness publish";
  };

  mutableState = {
    owner = "agent-state";
    runtimeRoot = "~/800_agents/state";
    syncCommand = "agent-harness sync";
    allowedRoots = [
      "MISTAKES.md"
      ".mistakes-dismissed.log"
      "projects/*/memory"
      # Agent workspace: each host writes only ledger/<host>.json; guard/ holds
      # arm.json and budgets.json, which only Eric edits.
      "ledger/*.json"
      "guard/*.json"
    ];
  };

  projectPolicy = {
    owner = "project-repository";
    roots = [
      "AGENTS.md"
      "CLAUDE.md"
    ];
  };

  # Agent programs and launchers come from the harness manifest ([programs]);
  # `kind`, `note` and `adds` describe the matrix, not ownership.
  providers = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = builtins.removeAttrs manifest.programs.${name} [ "kind" "note" "adds" ];
    }) (builtins.filter (name: manifest.programs.${name} ? policyOwner) (builtins.attrNames manifest.programs))
  );

  invariants = [
    "runtime-static-policy-never-references-authoring-repo"
    "system-and-user-policy-revisions-match"
    "mutable-state-never-contains-static-policy"
    "new-or-changed-memory-declares-authority-and-source"
    "one-owner-per-provider-integration"
  ];
}
