# secrets.nix — agenix recipient rules for nixos-hwc
#
# Recipient rules are GENERATED from the tree of *.age files under
# domains/secrets/parts/ (see domains/secrets/parts/lib.nix). Existing payloads default to
# `everyone`; offsite scopes exclude the storage-only host; the only hand-written rules are
# the caddy/ certs, kept explicit because their mounts use runtime hostname
# selection. Adding a secret = drop a .age into parts/<category>/ and rekey.
#
# After adding/removing a .age, run from this directory:
#   sudo agenix -r -i /etc/age/keys.txt
# to (re-)encrypt all secrets to the current recipient set.
#
# Key type note: host keys are age X25519 keys (matching /etc/age/keys.txt on
# each host). Eric's user key is SSH ed25519 (for agenix -e from a workstation).

let
  # Public host identities are shared with the generator's scope filter.
  laptop = gen.hostKeys.hwc-laptop;
  server = gen.hostKeys.hwc-home;
  work = gen.hostKeys.hwc-work;
  xps = gen.hostKeys.hwc-xps;

  # ── user keys ──
  eric = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPpGuiR4JKb0EyK8z+QmWo7qayRC01IHqUYspUbxgVgB eriqueo@homeserver";

  # ── recipient groups ──
  allHosts = [ server xps laptop work ];
  allUsers = [ eric ];
  everyone = allHosts ++ allUsers;

  gen = import ./domains/secrets/parts/lib.nix { };

  # Caddy TLS certs stay explicit: their mounts (parts/caddy.nix) select per
  # host at runtime. All four are readable by everyone (every host decrypts
  # everything; the xps certs were previously scoped to [ xps eric ] in error).
  caddyRecipients = {
    "domains/secrets/parts/caddy/hwc-server.ocelot-wahoo.ts.net.crt.age".publicKeys = everyone;
    "domains/secrets/parts/caddy/hwc-server.ocelot-wahoo.ts.net.key.age".publicKeys = everyone;
    "domains/secrets/parts/caddy/hwc-xps.ocelot-wahoo.ts.net.crt.age".publicKeys    = everyone;
    "domains/secrets/parts/caddy/hwc-xps.ocelot-wahoo.ts.net.key.age".publicKeys    = everyone;
  };

in
gen.mkRecipients {
  partsDir          = ./domains/secrets/parts;
  partsPrefix       = "domains/secrets/parts";
  inherit everyone caddyRecipients;
  recipientOverrides = gen.offsiteRecipientOverrides everyone;
}
