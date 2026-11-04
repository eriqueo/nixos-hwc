# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{

fleet-kernel-security = let
  fixture = pkgs.writeText "fleet-kernel-security.json" (builtins.toJSON
    (lib.mapAttrs (_: host: let c = host.config; in {
      kernel = c.boot.kernelPackages.kernel.version;
      tailscale = c.services.tailscale.package.version;
      openssl = host.pkgs.openssl.version;
      cacert = host.pkgs.cacert.version;
      mptcp = c.boot.kernel.sysctl."net.mptcp.enabled" or null;
      migration = c.boot.kernel.sysctl."net.ipv4.tcp_migrate_req" or null;
      # Inspect rendered policy, without building another architecture's
      # iptables merely because its store path occurs in this text.
      firewall = builtins.unsafeDiscardStringContext c.networking.firewall.extraCommands;
    }) self.nixosConfigurations));
in pkgs.runCommand "fleet-kernel-security" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} <<'PY'
  import copy, json, pathlib, sys
  def check(host, c):
      version = tuple(map(int, c['kernel'].split('.')[:3]))
      assert version[:2] == (6, 18) and version >= (6, 18, 60), (host, 'outdated kernel baseline', c['kernel'])
      # Tailscale Oct26 SSH/Serve fixes; OpenSSL Sep29 security release.
      # These are minimum fixed versions, not a substitute for CVE scans.
      assert tuple(map(int, c['tailscale'].split('.')[:3])) >= (1, 104, 4), (host, 'outdated Tailscale', c['tailscale'])
      ssl = tuple(map(int, c['openssl'].split('.')[:3]))
      ssl_floors = {(3, 0): (3, 0, 23), (3, 4): (3, 4, 8), (3, 5): (3, 5, 9), (3, 6): (3, 6, 5), (4, 0): (4, 0, 3)}
      assert ssl[:2] in ssl_floors and ssl >= ssl_floors[ssl[:2]], (host, 'unreviewed OpenSSL baseline', c['openssl'])
      assert tuple(map(int, c['cacert'].split('.'))) >= (3, 131, 1), (host, 'outdated trust bundle', c['cacert'])
      assert c['mptcp'] == 0 and c['migration'] == 0, (host, 'missing sysctl containment')
      for token in ['-w 5', '-t raw', 'PREROUTING', '-p tcp', '--u32', '0>>24&0xF=0x6:0xF', 'CVE-2026-98432-containment', '-j DROP']:
          assert token in c['firewall'], (host, 'missing early packet filter', token)
  configs = json.loads(pathlib.Path(sys.argv[1]).read_text())
  assert configs
  for host, c in configs.items():
      check(host, c)
      for key, value in [('kernel', '6.18.57'), ('tailscale', '1.104.2'), ('openssl', '3.6.4'), ('cacert', '3.130'), ('mptcp', 1), ('firewall', "")]:
          bad = copy.deepcopy(c); bad[key] = value
          try:
              check(host, bad)
          except AssertionError:
              pass
          else:
              raise AssertionError((host, 'seeded unsafe configuration accepted', key))
  print('all declared machines select reviewed kernel/Tailscale/OpenSSL baselines and persistent TCP containment')
  PY
  touch "$out"
'';

# The gateway must run the TypeScript build produced by Nix. Pointing
# systemd back at ignored checkout dist/ output recreates the stale-code
# failure this boundary removes. Referencing the entry point also builds
# the package, whose checkPhase runs the MCP test suite.
mcp-immutable-build = let
  # The gateway's host follows hwc.system.mcp.serverAlias (hwc-work since
  # service split wave 2), so the check reads that host's unit.
  fleet = self.nixosConfigurations.hwc-home.config.hwc;
  gatewayHost = fleet.networking.hosts.servers.${fleet.system.mcp.serverAlias};
  service = self.nixosConfigurations.${gatewayHost}.config.systemd.services.hwc-sys-mcp;
  command = service.serviceConfig.ExecStart;
  main = lib.last (lib.splitString " " command);
  n8n = service.environment.HWC_N8N_ENTRY_POINT;
in
assert lib.assertMsg (builtins.elem (builtins.dirOf service.environment.HWC_MAIL_SYNC_STATUS) service.serviceConfig.ReadWritePaths)
  "mcp-immutable-build: shared mail owner lock must be writable inside the gateway sandbox";
assert lib.assertMsg (lib.hasPrefix "/nix/store/" main)
  "mcp-immutable-build: gateway entry point is not in the Nix store";
assert lib.assertMsg (!(lib.hasInfix "/home/eric/.nixos/" main))
  "mcp-immutable-build: gateway returned to mutable checkout dist output";
assert lib.assertMsg (lib.hasPrefix "/nix/store/" n8n && !(service.serviceConfig ? ExecStartPre))
  "mcp-immutable-build: n8n backend must be immutable with no startup installer";
pkgs.runCommand "mcp-immutable-build" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  test -f ${main}
  timeout 45 ${service.environment.HWC_NODE_PATH} \
    ${(repoRoot + "/domains/system/mcp/parts/n8n-mcp/smoke.mjs")} \
    ${n8n} ${service.environment.HWC_NODE_PATH}
  touch "$out"
'';

journal-retention = let
  work = self.nixosConfigurations.hwc-work;
  home = self.nixosConfigurations.hwc-home.config;
  # A host override must still win over the capability's default.
  override = (work.extendModules {
    modules = [ { services.journald.extraConfig = "SystemMaxUse=2G"; } ];
  }).config.services.journald.extraConfig;
in
assert lib.assertMsg (lib.hasInfix "SystemMaxUse=1G" work.config.services.journald.extraConfig)
  "journal-retention: work has no explicit default ceiling";
assert lib.hasInfix "SystemMaxUse=8G" home.services.journald.extraConfig;
assert override == "SystemMaxUse=2G";
pkgs.runCommand "journal-retention" {} ''touch "$out"'';
}
