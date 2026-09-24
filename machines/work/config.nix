# hwc-work — staged MS-02 work server. Production service ownership remains
# on hwc-server until a service is migrated with its state and callers.
{ ... }: {
  imports = [
    ./hardware.nix
    # Notification routes need the networking domain's shared vocabulary,
    # even while this host's reverse proxy remains disabled.
    ../../domains/networking/index.nix
  ];

  networking.hostName = "hwc-work";
  system.stateVersion = "25.11";

  # The server role supplies Podman, CLI tools and server path defaults. These
  # three role defaults would otherwise create a second live stateful writer.
  hwc.data.couchdb.enable = false;
  hwc.automation.nightlyBuilds.enable = false;
  hwc.automation.refinery.enable = false;
  hwc.mail.protonmailBridgeCert.enable = false;

  # No storage tiers, production routes or scheduled business services are
  # enabled until the drives and ownership for each service are established.
  hwc.system.networking.waitOnline.mode = "all";
  hwc.system.networking.waitOnline.timeoutSeconds = 30;
}
