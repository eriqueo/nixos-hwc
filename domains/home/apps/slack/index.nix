# domains/home/apps/slack/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "slack";
  description = "Slack desktop client";
  package = pkgs: pkgs.slack;
}
