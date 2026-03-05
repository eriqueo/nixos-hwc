# domains/automation/index.nix
#
# Automation domain — workflow automation and notification services.
#
# Namespace: hwc.automation.{n8n,ntfy}.*

{ lib, config, ... }:

{
  imports = [
    ./n8n/index.nix
    ./ntfy/index.nix    # MOVED from domains/system/services/ntfy
  ];
}
