# domains/automation/index.nix
#
# Automation domain — workflow engine and event bus.
#
# Namespace: hwc.automation.{n8n,mqtt,nightlyBuilds}.*

{ lib, config, ... }:

{
  imports = [
    ./mqtt/index.nix
    ./n8n/index.nix
    ./nightly-builds/index.nix
  ];
}
