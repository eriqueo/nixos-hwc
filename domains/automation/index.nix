# domains/automation/index.nix
#
# Automation domain — workflow automation and notification services.
#
# Namespace: hwc.automation.{n8n,gotify}.*

{ lib, config, ... }:

{
  imports = [
    ./mqtt/index.nix
    ./n8n/index.nix
    ./gotify/index.nix   # Gotify notification CLI (replaces ntfy)
  ];
}
