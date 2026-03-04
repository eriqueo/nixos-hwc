# domains/automation/index.nix
#
# Automation domain — workflow automation services.
# Currently contains n8n for alert routing and webhook handling.
#
# Namespace: hwc.automation.n8n.*

{ lib, config, ... }:

{
  imports = [
    ./n8n/index.nix
  ];
}
