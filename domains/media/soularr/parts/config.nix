# Preserve saved choices while managing service addresses and credentials.
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.soularr;
  slskdCfg = config.hwc.media.slskd;
  soularrRoot = "${config.hwc.paths.apps.root}/soularr";

  # soularr sits on media-network; slskd does not. Once slskd moved into the
  # tunnel's netns it stopped having an interface — and therefore a DNS name —
  # of its own, so the address is the TUNNEL's alias. Derived from slskd's own
  # options so the two cannot drift when the instance is renamed.
  slskdUrl =
    if slskdCfg.network.mode == "vpn"
    then "http://${slskdCfg.vpnInstance}:5030"
    else "http://slskd:5030";
  spec = pkgs.writeText "soularr-config-inputs.json" (builtins.toJSON {
    path = "${soularrRoot}/data/config.ini";
    group = "secrets";
    services = {
      Lidarr = { url = "http://lidarr:8686"; keyFile = config.age.secrets.lidarr-api-key.path; };
      Slskd = { url = slskdUrl; keyFile = config.age.secrets.slskd-api-key.path; };
    };
  });
  updater = pkgs.writeText "soularr-config-update.py" ''
    import configparser, grp, json, os, pathlib, stat, sys, tempfile

    class ConfigError(Exception):
        pass

    def parse(text):
        parser = configparser.RawConfigParser(strict=True, empty_lines_in_values=False)
        parser.read_string(text)
        return parser

    def snapshot(parser):
        return (dict(parser.defaults()),
                {section: dict(parser.items(section, raw=True)) for section in parser.sections()})

    def render(text, managed, defaults):
        original = parse(text)
        expected = parse(text)
        additions = {}
        for section, values in managed.items():
            if not expected.has_section(section):
                expected.add_section(section)
            updates = dict(values)
            updates.update({key: value for key, value in defaults[section].items()
                            if not expected.has_option(section, key)})
            additions[section] = dict(updates)
            for key, value in updates.items():
                expected.set(section, key, value)

        # Use ConfigParser's vocabulary; post-validation rejects unsupported
        # multiline managed values before any write, rather than losing settings.
        lines, section = [], None
        def finish(current):
            if current in additions:
                for key, value in additions[current].items():
                    lines.append(key + ' = ' + value + '\n')
                additions[current].clear()
        for line in text.splitlines(keepends=True):
            stripped = line.strip()
            header = original.SECTCRE.match(stripped)
            if stripped and not stripped.startswith(('#', ';')) and header:
                finish(section)
                section = header.group('header')
            elif stripped and not stripped.startswith(('#', ';')) and section in additions:
                option = original.OPTCRE.match(line)
                if option:
                    key = original.optionxform(option.group('option').strip())
                    if key in additions[section]:
                        start, end = option.span('value')
                        line = line[:start] + additions[section].pop(key) + line[end:]
            lines.append(line if line.endswith('\n') else line + '\n')
        finish(section)
        for missing, values in additions.items():
            if not original.has_section(missing):
                lines.append('\n[' + missing + ']\n')
                lines.extend(key + ' = ' + value + '\n' for key, value in values.items())
        result = "".join(lines)
        if snapshot(parse(result)) != snapshot(expected):
            raise ConfigError('SOULARR_CONFIG_PRESERVATION')
        return result

    def read_bounded(path, limit):
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as source:
            identity = os.fstat(source.fileno())
            if not stat.S_ISREG(identity.st_mode) or identity.st_size > limit:
                raise ConfigError('SOULARR_CONFIG_INPUT')
            data = source.read(limit + 1)
        if len(data) > limit:
            raise ConfigError('SOULARR_CONFIG_INPUT')
        return data, identity

    def update(spec):
        path = pathlib.Path(spec['path'])
        gid = grp.getgrnam(spec['group']).gr_gid
        managed = {}
        for section, service in spec['services'].items():
            data, _ = read_bounded(service['keyFile'], 1024)
            key = data.decode('ascii').rstrip('\n')
            if not key or '\n' in key or '\r' in key or any(ord(c) < 33 or ord(c) > 126 for c in key):
                raise ConfigError('SOULARR_CONFIG_KEY')
            managed[section] = {'host_url': service['url'], 'api_key': key}
        managed['General'] = {}
        defaults = {'Lidarr': {'download_dir': '/downloads/music'},
                    'Slskd': {'download_dir': '/downloads/music'}, 'General': {'interval': '300'}}
        try:
            before, identity = read_bounded(path, 1024 * 1024)
        except FileNotFoundError:
            before, identity = b"", None
        result = render(before.decode('utf-8'), managed, defaults).encode('utf-8')
        if len(result) > 1024 * 1024:
            raise ConfigError('SOULARR_CONFIG_SIZE')
        if identity and before == result and stat.S_IMODE(identity.st_mode) == 0o440 and identity.st_gid == gid:
            return
        temporary = None
        try:
            fd, temporary = tempfile.mkstemp(prefix='.config-', dir=path.parent)
            with os.fdopen(fd, 'wb') as output:
                output.write(result)
                output.flush()
                os.fchown(output.fileno(), -1, gid)
                os.fchmod(output.fileno(), 0o440)
                os.fsync(output.fileno())
            current = path.lstat() if path.exists() or path.is_symlink() else None
            if ((current is None) != (identity is None) or
                (current and (current.st_dev, current.st_ino, current.st_mtime_ns, current.st_size)
                 != (identity.st_dev, identity.st_ino, identity.st_mtime_ns, identity.st_size))):
                raise ConfigError('SOULARR_CONFIG_CHANGED')
            os.replace(temporary, path)
            temporary = None
        finally:
            if temporary is not None:
                os.unlink(temporary)

    if __name__ == '__main__':
        try:
            update(json.loads(pathlib.Path(sys.argv[1]).read_text()))
        except Exception as error:
            # Parser/OSError messages can contain credentials. Emit only a code.
            print(str(error) if isinstance(error, ConfigError) else 'SOULARR_CONFIG_INVALID', file=sys.stderr)
            sys.exit(1)
  '';
in
{
  config = lib.mkIf cfg.enable {
    system.build.soularrConfigUpdater = updater;
    systemd.services.soularr-config = {
      description = "Update Soularr credentials and preserve saved settings";
      wantedBy = [ "podman-soularr.service" ];
      before = [ "podman-soularr.service" ];
      after = [ "agenix.service" "systemd-tmpfiles-setup.service" ];
      wants = [ "agenix.service" ];
      restartTriggers = [ config.age.secrets.lidarr-api-key.file config.age.secrets.slskd-api-key.file ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = lib.mkForce "eric";
        Group = "users";
        SupplementaryGroups = [ "secrets" ];
        UMask = "0077";
        TimeoutStartSec = "30s";
        MemoryMax = "256M";
        CPUQuota = "100%";
        TasksMax = 32;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "${soularrRoot}/data" ];
        ExecStart = "${pkgs.python3}/bin/python3 ${updater} ${spec}";
      };
    };
  };
}
