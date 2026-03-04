# domains/automation/index.nix
#
# Automation domain — workflow automation services.
# Currently contains n8n for alert routing and webhook handling.
#
# Namespace: hwc.server.native.n8n.*
# TODO Phase 8: Migrate to hwc.automation.n8n.*

{ lib, config, ... }:

{
  imports = [
    ./n8n/index.nix
  ];
}
