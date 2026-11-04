# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{

vaultwarden-runtime-wiring = let
  c = self.nixosConfigurations.hwc-work.config;
  container = c.virtualisation.oci-containers.containers.vaultwarden;
  data = "${c.hwc.paths.state}/vaultwarden/data";
in
assert lib.assertMsg
  (container.image == "docker.io/vaultwarden/server@sha256:f8863ab2519364bfc657144006682a830784e0bb501606d5e34516ee76b60b5c")
  "Vaultwarden must consume its qualified 1.37.5 security image";
assert container.image == c.hwc.secrets.vaultwarden.image;
assert lib.elem "${data}:/data:rw" container.volumes;
assert c.hwc.data.borg.sqliteSnapshots.vaultwarden.source == "${data}/db.sqlite3";
assert c.hwc.data.borg.sqliteSnapshots.vaultwarden.user == "root";
assert lib.elem data c.hwc.data.borg.sources;
assert lib.elem "--security-opt=no-new-privileges" container.extraOptions;
assert container.environment.DOMAIN == "https://vaultwarden.${c.hwc.networking.shared.vhostDomain}";
assert container.environment.SIGNUPS_ALLOWED == "false";
assert container.environment.INVITATIONS_ALLOWED == "true";
assert container.environment.SHOW_PASSWORD_HINT == "false";
assert container.ports == [ "127.0.0.1:${toString c.hwc.secrets.vaultwarden.port}:80" ];
pkgs.runCommand "vaultwarden-runtime-wiring" {} "touch $out";
secrets-offsite-scope = let
  gen = import (repoRoot + "/domains/secrets/parts/lib.nix") {};
  everyone = builtins.attrValues gen.hostKeys ++ [ "ssh-ed25519 recovery-user-fixture" ];
  recipients = gen.offsiteRecipientOverrides everyone;
  names = builtins.attrNames gen.offsiteScopes;
in
assert builtins.length names == 6;
assert lib.all (name:
  !(gen.mountAllowed "hwc-xps" name)
  && !(gen.mountAllowed "unknown-host" name)
  && lib.all (host: gen.mountAllowed host name) [ "hwc-home" "hwc-work" "hwc-laptop" ]
  && !(lib.elem gen.hostKeys.hwc-xps recipients.${name})
  && lib.elem "ssh-ed25519 recovery-user-fixture" recipients.${name}
  && lib.all (host: lib.elem gen.hostKeys.${host} recipients.${name}) [ "hwc-home" "hwc-work" "hwc-laptop" ]
) names;
assert gen.mountAllowed "hwc-xps" "borg-passphrase";
pkgs.runCommand "secrets-offsite-scope" {} ''touch $out'';
}
