# domains/automation/index.nix
#
# Automation domain — workflow engine and event bus.
#
# Namespace: hwc.automation.{n8n,mqtt,nightlyBuilds,readmeFreshness,refinery,srGauntlet,dx1Gauntlet,vaultSync,inboxJanitor,mailJanitor}.*

{ lib, config, ... }:

{
  imports = [
    ./brain-sweep/index.nix
    ./dx1-gauntlet/index.nix
    ./inbox-janitor/index.nix
    ./mail-janitor/index.nix
    ./mqtt/index.nix
    ./n8n/index.nix
    ./nightly-builds/index.nix
    ./readme-freshness/index.nix
    ./refinery/index.nix
    ./sr-gauntlet/index.nix
    ./vault-sync/index.nix
  ];
}
