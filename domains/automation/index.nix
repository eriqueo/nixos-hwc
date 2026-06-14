# domains/automation/index.nix
#
# Automation domain — workflow engine and event bus.
#
# Namespace: hwc.automation.{n8n,mqtt,nightlyBuilds,readmeFreshness,refinery,srGauntlet}.*

{ lib, config, ... }:

{
  imports = [
    ./mqtt/index.nix
    ./n8n/index.nix
    ./nightly-builds/index.nix
    ./readme-freshness/index.nix
    ./refinery/index.nix
    ./sr-gauntlet/index.nix
  ];
}
