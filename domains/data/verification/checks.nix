# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{

postgresql-owned-host-auth-wiring = let
  hosts = [ "hwc-work" "hwc-home" "hwc-laptop" ];
  binding = c: {
    mode = c.hwc.data.databases.postgresql.authenticationMode;
    containerNetwork = c.hwc.data.databases.postgresql.containerNetwork.enable;
    inherit (c.services.postgresql) authentication identMap;
  };
  fixtures = pkgs.writeText "postgresql-owned-host-auth-wiring.json" (builtins.toJSON {
    current = lib.genAttrs hosts (name: binding self.nixosConfigurations.${name}.config);
    legacy = lib.genAttrs hosts (name: binding (self.nixosConfigurations.${name}.extendModules {
      modules = [ { hwc.data.databases.postgresql.authenticationMode = lib.mkForce "legacy-trust"; } ];
    }).config);
  });
in pkgs.runCommand "postgresql-owned-host-auth-wiring" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  python - ${fixtures} <<'PY'
  import json, pathlib, sys
  fixtures = json.loads(pathlib.Path(sys.argv[1]).read_text())
  assert len(fixtures['current']) == 3
  def check(config):
    assert config['mode'] == 'peer-scram'
    lines = [line.split() for line in config['authentication'].splitlines()
      if line.strip() and not line.lstrip().startswith('#')]
    assert lines[0] == ['local', 'all', 'postgres', 'peer', 'map=postgres']
    assert ['local', 'all', 'all', 'peer'] in lines
    assert not any(token in {'trust', 'md5'} for line in lines for token in line)
    tcp = [line for line in lines if line[0] == 'host']
    expected = {'127.0.0.1/32', '::1/128'}
    if config['containerNetwork']:
      expected.add('10.89.0.0/16')
    assert {line[3] for line in tcp} == expected
    assert all(line[:3] == ['host', 'all', 'all'] and line[4:] == ['scram-sha-256'] for line in tcp)
    assert 'postgres postgres postgres' in config['identMap']
  for name, config in fixtures['current'].items():
    check(config)
    try:
      check(fixtures['legacy'][name])
    except AssertionError:
      pass
    else:
      raise AssertionError('LEGACY_TRUST_ACCEPTED:' + name)
    broken = {**config, 'authentication': config['authentication'] + '\nhost all all 127.0.0.1/32 trust\n'}
    try:
      check(broken)
    except AssertionError:
      pass
    else:
      raise AssertionError('TRUST_RULE_ACCEPTED:' + name)
  PY
  touch "$out"
'';

postgresql-work-auth-wiring = let
  c = self.nixosConfigurations.hwc-work.config;
  db = c.hwc.data.databases.postgresql;
  operator = c.systemd.services.postgresql-application-roles;
  dependency = "postgresql-application-roles.service";
  apps = [ "firefly" "firefly-pico" "paperless" "umami" "n8n" ];
  clients = lib.filterAttrs (_: unit:
    unit.environment ? DATABASE_URL || unit.environment ? HWC_LEADS_PG_DSN)
    c.systemd.services;
  fixture = pkgs.writeText "postgresql-work-auth-wiring.json" (builtins.toJSON {
    inherit (c.services.postgresql) authentication identMap ensureUsers;
    peerRoles = db.localPeerRoles;
    roles = db.applicationRoles;
    containers = lib.genAttrs apps (name: {
      inherit (c.virtualisation.oci-containers.containers.${name}) environment environmentFiles;
    });
    native = lib.mapAttrs (_: unit: {
      inherit (unit) after requires;
      environment = builtins.intersectAttrs {
        DATABASE_URL = null; HWC_LEADS_PG_DSN = null;
        PGHOST = null; PGPORT = null; PGUSER = null;
      } unit.environment;
    }) clients;
    fireflyPreStart = c.systemd.services.podman-firefly.preStart;
    n8nPreStart = c.systemd.services.podman-n8n.preStart;
  });
in
assert db.authenticationMode == "peer-scram";
assert builtins.attrNames db.applicationRoles == [ "firefly" "firefly_pico" "n8n" "paperless" "umami" ];
assert lib.all (name: let unit = c.systemd.services."podman-${name}"; in
  builtins.elem dependency unit.after && builtins.elem dependency unit.requires
  && builtins.elem c.system.build.postgresqlApplicationRoleTool unit.restartTriggers) apps;
assert builtins.elem c.system.build.postgresqlApplicationRoleTool operator.restartTriggers;
assert builtins.elem "postgresql-setup.service" operator.after && builtins.elem "postgresql-setup.service" operator.requires;
assert lib.all (name: let unit = c.systemd.services.${name}; in
  builtins.elem "postgresql-setup.service" unit.after
  && builtins.elem "postgresql-setup.service" unit.requires
  && unit.environment.PGHOST == db.localPeerEnvironment.PGHOST)
  [ "hwc-crm" "hwc-crm-leadscout-ingest" ];
assert c.virtualisation.oci-containers.containers.n8n.environment.DB_TYPE == "sqlite";
assert lib.all (name: let secret = c.age.secrets.${name}; in
  secret.owner == "root" && secret.group == "secrets" && secret.mode == "0440")
  [ "firefly-db-env" "firefly-pico-db-env" "paperless-db-env" "n8n-postgres-env" "umami-env" ];
pkgs.runCommand "postgresql-work-auth-wiring" {
  nativeBuildInputs = [ c.system.build.postgresqlApplicationRolePython ];
} ''
  python - ${fixture} ${c.system.build.postgresqlApplicationRoleConfig} ${c.system.build.postgresqlApplicationRoleContract} ${(repoRoot + "/domains/data/databases/application-roles.py")} ${c.system.build.n8nPostgresqlCredentialConfig} ${(repoRoot + "/domains/automation/n8n/postgres-credentials.py")} ${(repoRoot + "/domains/automation/n8n/parts/migrations/004-workflow-run-metadata.sql")} ${c.systemd.services.paperless-env.serviceConfig.ExecStart} <<'PY'
  import importlib.util, json, pathlib, sys
  binding, config, contract = [json.loads(pathlib.Path(p).read_text()) for p in sys.argv[1:4]]
  module_spec = importlib.util.spec_from_file_location('roles', sys.argv[4])
  module = importlib.util.module_from_spec(module_spec)
  sys.modules[module_spec.name] = module
  module_spec.loader.exec_module(module)
  parsed = module.parse_roles(config, 'eric', contract)
  assert len(parsed) == 5 and config['roles'] == binding['roles']
  legacy = {name: spec['authority']['owned'] for name, spec in config['roles'].items()
    if 'owned' in spec['authority']}
  try:
    module.parse_roles(legacy, 'eric', contract)
  except module.ContractError as error:
    assert error.code == 'CONFIG_VERSION_INVALID'
  else:
    raise AssertionError('UNVERSIONED_ROLE_CONFIG_ACCEPTED')
  assert config['roles']['n8n']['prepareSql'] == pathlib.Path(sys.argv[7]).read_text()
  assert 'ADD COLUMN IF NOT EXISTS metadata jsonb' in config['roles']['n8n']['prepareSql']
  lines = [line.split() for line in binding['authentication'].splitlines() if line.strip() and not line.lstrip().startswith('#')]
  assert not any('trust' in line or 'md5' in line for line in lines)
  assert all(line[-1] == 'scram-sha-256' for line in lines if line[0] == 'host')
  for role, database in binding['peerRoles'].items():
    assert ['local', database, role, 'peer', 'map=hwc-apps'] in lines
    assert 'hwc-apps eric ' + role in binding['identMap']
  for name, client in binding['native'].items():
    env = client['environment']
    assert env['PGHOST'] == '/run/postgresql' and env['PGPORT'] == '5432', name
    assert 'postgresql-setup.service' in client['after'] or 'datax-monitor-migrate.service' in client['after'], name
    dsn = env.get('DATABASE_URL', env.get('HWC_LEADS_PG_DSN'))
    assert dsn.startswith('postgresql:///'), name
    if 'PGUSER' in env:
      assert dsn == 'postgresql:///' + binding['peerRoles'][env['PGUSER']], name
  assert binding['containers']['firefly']['environment']['DB_USERNAME'] == 'firefly'
  assert binding['containers']['firefly-pico']['environment']['DB_USERNAME'] == 'firefly_pico'
  for app, role in [('firefly','firefly'),('firefly-pico','firefly_pico'),('paperless','paperless'),('umami','umami'),('n8n','n8n')]:
    source = binding['roles'][role]['credential']['environment']['secret']
    assert '/run/agenix/' + source in binding['containers'][app]['environmentFiles']
  assert 'PAPERLESS_DBUSER=paperless' in pathlib.Path(sys.argv[8]).read_text()
  assert 'chmod 600' in binding['fireflyPreStart'] and 'chmod 644' not in binding['fireflyPreStart']
  n8n = json.loads(pathlib.Path(sys.argv[5]).read_text())
  assert len(n8n['credentialIds']) == 2 and n8n['database'] == 'hwc'
  assert n8n['desired'] == {'host':'localhost','port':5432,'user':'n8n','password':'={{ $env.HWC_POSTGRES_PASSWORD }}'}
  assert sys.argv[5] in binding['n8nPreStart'] and sys.argv[6] in binding['n8nPreStart']
  assert all(not user.get('ensureClauses', {}).get('superuser', False)
    for user in binding['ensureUsers'] if user['name'] in binding['roles'] or user['name'] in binding['peerRoles'])
  PY
  touch "$out"
'';
}
