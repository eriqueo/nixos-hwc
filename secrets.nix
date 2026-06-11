# secrets.nix — agenix recipient rules for nixos-hwc
#
# Recipient rules are GENERATED from the tree of *.age files under
# domains/secrets/parts/ (see domains/secrets/parts/lib.nix). Every secret is
# readable by `everyone` (all hosts + eric); the only hand-written rules are
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
  # ── helpers ──
  readKey = f: builtins.replaceStrings [ "\n" "\r" ] [ "" "" ] (builtins.readFile f);

  # ── machine host keys (age public keys matching /etc/age/keys.txt on each host) ──
  laptop = readKey ./machines/laptop/AGE_PUBLIC_KEY.txt;
  server = readKey ./machines/server/AGE_PUBLIC_KEY.txt;
  xps    = readKey ./machines/xps/AGE_PUBLIC_KEY.txt;

  # ── user keys ──
  eric = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPpGuiR4JKb0EyK8z+QmWo7qayRC01IHqUYspUbxgVgB eriqueo@homeserver";

  # ── recipient groups ──
  allHosts = [ server xps laptop ];
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
  recipientOverrides = { };
}
