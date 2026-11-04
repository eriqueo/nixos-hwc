{ self, inputs, lib, system, checkRuntimeScope, channels, keymapDocs, keymapDocsApp, laptopRuntimeScope, machines, mailHost, mailMachines, mailOwner, pkgs-firestick, pkgs-laptop, pkgs-stable, pkgs-stable-cuda, serverCudaRuntimeScope, serverRuntimeScope }:
let
  repoRoot = ../../..;
  pkgs = checkRuntimeScope.pkgs;
  mailHome = self.nixosConfigurations.${mailHost}.config.home-manager.users.eric;
  keymap = import ../../../domains/home/keymap/verification/helpers.nix { inherit lib pkgs repoRoot; };
  context = { inherit self inputs lib system pkgs repoRoot mailHome channels keymapDocs keymapDocsApp laptopRuntimeScope machines mailHost mailMachines mailOwner pkgs-firestick pkgs-laptop pkgs-stable pkgs-stable-cuda serverCudaRuntimeScope serverRuntimeScope; inherit (keymap) keymapGrammar keymapValidator keymapGrammarFile; };
  group = owner: kind: file:
    let f = import file; in lib.mapAttrs (name: derivation:
      { inherit owner derivation; kind = if kind == "domain" then "integration" else kind; }
      // lib.optionalAttrs (name == "n8n-route-compatibility") {
        kind = "compatibility";
        retirement = "Remove legacy-port assertions only after all former-owner n8n clients use the work endpoint; retain owner/firewall contracts.";
      })
      (f (builtins.intersectAttrs (builtins.functionArgs f) context));
  groups = [
    (group "workspace/nixos-dev" "shared" (repoRoot + "/workspace/nixos-dev/verification/checks.nix"))
    (group "domains/media" "domain" (repoRoot + "/domains/media/verification/checks.nix"))
    (group "domains/networking" "domain" (repoRoot + "/domains/networking/verification/checks.nix"))
    (group "domains/business" "domain" (repoRoot + "/domains/business/verification/checks.nix"))
    (group "domains/home" "domain" (repoRoot + "/domains/home/verification/checks.nix"))
    (group "domains/system" "domain" (repoRoot + "/domains/system/verification/checks.nix"))
    (group "domains/secrets" "domain" (repoRoot + "/domains/secrets/verification/checks.nix"))
    (group "domains/data" "domain" (repoRoot + "/domains/data/verification/checks.nix"))
    (group "domains/automation" "domain" (repoRoot + "/domains/automation/verification/checks.nix"))
    (group "domains/mail" "domain" (repoRoot + "/domains/mail/verification/checks.nix"))
    (group "domains/home/keymap" "domain" (repoRoot + "/domains/home/keymap/verification/checks.nix"))
    (group "domains/server" "domain" (repoRoot + "/domains/server/verification/checks.nix"))
    (group "domains/monitoring" "domain" (repoRoot + "/domains/monitoring/verification/checks.nix"))
    (group "domains/server/services/meals" "domain" (repoRoot + "/domains/server/services/meals/verification/checks.nix"))
    (group "workspace/nixos-dev" "governance" (repoRoot + "/workspace/nixos-dev/verification/governance.nix"))
    (group "domains/data/borg" "domain" (repoRoot + "/domains/data/borg/verification/checks.nix"))
  ];
  registry = import ./registry.nix { inherit lib repoRoot groups; };
in {
  inherit registry;
  checks = lib.mapAttrs (_: entry: entry.derivation) registry;
  inventory = lib.mapAttrs (_: entry: builtins.removeAttrs entry [ "derivation" ]) registry;
}
