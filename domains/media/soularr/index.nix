{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.soularr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  # Same deployed CLI, smaller same-ABI runtime. Immutable app/runtime pins are
  # permanent by design; replace only after current-data recovery qualification.
  # Remove the framing adapter when unmodified vendor clients pass the actual
  # malformed/normal-response and current-data recovery contracts.
  spec = {
    schemaVersion = 1;
    pythonVersion = "3.11.18";
    sourceImage = "docker.io/mrusse08/soularr@sha256:894210817cd89dd410fa603be2744ca81c593b9eaa542639a7894f2df008a788";
    baseImage = "docker.io/library/python@sha256:6d10e720318bd84cc3d88af92bb5a47189222e17620a2fd214da6445e4afb679";
    appFiles = {
      "soularr.py" = "74fbda54d8bcfed743685fb9f317e756ce307787d12047967decda2fd05add70";
      "run.sh" = "6e44200afa5f3fc41511f10ad609bb76e07a805f27069f74eb2dbc631528e0bd";
    };
    preservedPackages = [
      { name = "charset-normalizer"; module = "charset_normalizer"; version = "3.4.3"; }
      { name = "idna"; module = "idna"; version = "3.10"; }
      { name = "music-tag"; module = "music_tag"; version = "0.4.3"; }
      { name = "mutagen"; module = "mutagen"; version = "1.47.0"; }
      { name = "overrides"; module = "overrides"; version = "7.7.0"; }
      { name = "pyarr"; module = "pyarr"; version = "5.2.0"; }
      { name = "slskd-api"; module = "slskd_api"; version = "0.1.5"; }
      { name = "types-requests"; module = "requests-stubs"; version = "2.32.4.20250809"; }
    ];
    wheels = [
      { name = "requests"; version = "2.34.2"; filename = "requests-2.34.2-py3-none-any.whl";
        url = "https://files.pythonhosted.org/packages/a0/f4/c67b0b3f1b9245e8d266f0f112c500d50e5b4e83cb6f3b71b6528104182a/requests-2.34.2-py3-none-any.whl";
        sha256 = "2a0d60c172f83ac6ab31e4554906c0f3b3588d37b5cb939b1c061f4907e278e0"; }
      { name = "urllib3"; version = "2.8.0"; filename = "urllib3-2.8.0-py3-none-any.whl";
        url = "https://files.pythonhosted.org/packages/92/9d/c4e665119135114480843e7ab388fa94d8480650450e6f8e26b70d323a4c/urllib3-2.8.0-py3-none-any.whl";
        sha256 = "0cf3cae568d36aa9576b28dfb35f11328f1cb974ca7647d9475ebb86c75ac6e3"; }
      { name = "certifi"; version = "2026.10.23"; filename = "certifi-2026.10.23-py3-none-any.whl";
        url = "https://files.pythonhosted.org/packages/32/d1/a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/certifi-2026.10.23-py3-none-any.whl";
        sha256 = "e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1"; }
    ];
    debs = [
      { name = "libproc2-0"; filename = "libproc2-0_4.0.4-9_amd64.deb";
        url = "https://deb.debian.org/debian/pool/main/p/procps/libproc2-0_4.0.4-9_amd64.deb";
        sha256 = "c9d61caab1b2ddfc3f17edb95be31b9809fcb2daf27d853dff615bc4ebd08b4b"; }
      { name = "procps"; filename = "procps_4.0.4-9_amd64.deb";
        url = "https://deb.debian.org/debian/pool/main/p/procps/procps_4.0.4-9_amd64.deb";
        sha256 = "4db90bb6776772fc52585d6b1fbfc52ec2a85480e1b4363b743fbb2ffa2a5375"; }
      { name = "tini"; filename = "tini_0.19.0-3+b8_amd64.deb";
        url = "https://deb.debian.org/debian/pool/main/t/tini/tini_0.19.0-3+b8_amd64.deb";
        sha256 = "a443b12107331f67836a64cb6efe1dd92d2765e15568eb4567dccb409a8cd2a0"; }
    ];
  };
  site = "/usr/local/lib/python3.11/site-packages";
  urllib3Wheel = lib.findFirst (entry: entry.name == "urllib3") (throw "Soularr requires its urllib3 wheel") spec.wheels;
  framing = helpers.mkPythonHttpFramingBackport {
    python = "/usr/local/bin/python3";
    stdlibUpstreamCommits = pkgs.pythonHttpFramingBackport.upstreamCommits;
    modules = {
      httpClient = {
        path = "/usr/local/lib/python3.11/http/client.py";
        sourceSha256 = "1d41c7caf2d3b263a6e1e313120db4c8fc5021c0c9783ee861bf1a43c9cde5d8";
        patchedSha256 = "19c30ad49586aebc0a1be8a21dd27718789105870bfe4d9ebb9530aac8bc7a79";
        replacements = pkgs.pythonHttpFramingBackport.replacements;
      };
      urllib3 = {
        path = "${site}/urllib3/response.py";
        inherit (pkgs.pythonUrllib3FramingBackport.sources.${urllib3Wheel.version}) sourceSha256 patchedSha256;
        replacements = pkgs.pythonUrllib3FramingBackport.replacements;
      };
    };
  };
  guard = ''
    import hashlib, importlib.metadata, json, sys
    from pathlib import Path
    def verify(spec, app, inputs, version):
        assert spec['schemaVersion'] == 1 and version == spec['pythonVersion'], 'SOULARR_RUNTIME_VERSION'
        for name, digest in spec['appFiles'].items():
            path = app / name
            assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 131072, 'SOULARR_APP_BOUND'
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'SOULARR_APP_SOURCE'
        for entry in spec['wheels'] + spec['debs']:
            path = inputs / entry['filename']
            assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 2097152, 'SOULARR_INPUT_BOUND'
            assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], 'SOULARR_INPUT_SOURCE'
        for entry in spec['preservedPackages']:
            assert importlib.metadata.version(entry['name']) == entry['version'], 'SOULARR_PACKAGE_VERSION'
    if __name__ == '__main__':
        verify(json.loads(Path(sys.argv[1]).read_text()), Path('/app'), Path('/tmp/hwc-soularr'), sys.version.split()[0])
  '';
  guardSource = pkgs.writeText "soularr-runtime-input-guard.py" guard;
  manifest = spec // { framing = framing.manifest; };
  manifestSource = pkgs.writeText "soularr-runtime.json" (builtins.toJSON manifest);
  # COPY only the existing runtime owners. Build tools and their vendored code
  # never cross from the old full buildpack image into this runtime.
  copies = lib.concatMapStrings (entry:
    let info = "${lib.replaceStrings [ "-" ] [ "_" ] entry.name}-${entry.version}.dist-info";
    in "COPY --from=app-source ${site}/${entry.module}/ ${site}/${entry.module}/\n"
      + "COPY --from=app-source ${site}/${info}/ ${site}/${info}/\n") spec.preservedPackages;
  runtime = helpers.mkRuntimeImage {
    name = "soularr";
    version = "cli-20250815-python${spec.pythonVersion}";
    recipe = ''
      FROM ${spec.sourceImage} AS app-source
      FROM ${spec.baseImage}
      COPY --from=app-source /app/soularr.py /app/run.sh /app/
    '' + copies + ''
      COPY inputs/ /tmp/hwc-soularr/
      RUN python3 -B /tmp/hwc-soularr/guard.py /tmp/hwc-soularr/manifest.json
      RUN dpkg -i ${lib.concatMapStringsSep " " (entry: "/tmp/hwc-soularr/${entry.filename}") spec.debs}
      RUN python3 -m pip install --no-index --no-deps --no-compile --disable-pip-version-check ${lib.concatMapStringsSep " " (entry: "/tmp/hwc-soularr/${entry.filename}") spec.wheels} && python3 -m pip check && python3 -m pip uninstall --yes pip setuptools wheel
    '' + framing.recipe + ''
      RUN python3 -B /app/soularr.py --help && ps aux >/dev/null && tini --version
      RUN rm -rf /tmp/hwc-soularr
      WORKDIR /app
      ENV PYTHONDONTWRITEBYTECODE=1
      ENTRYPOINT ["tini", "-g", "--"]
      CMD ["/app/run.sh"]
    '';
  };
  context = pkgs.runCommand "soularr-runtime-context" {} ''
    mkdir -p "$out/inputs"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${manifestSource} "$out/inputs/manifest.json"
    cp ${guardSource} "$out/inputs/guard.py"
    ${lib.concatMapStringsSep "\n" (entry:
      "cp ${pkgs.fetchurl { inherit (entry) url sha256; }} \"$out/inputs/${entry.filename}\"") (spec.wheels ++ spec.debs)}
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.soularr = {
    enable = lib.mkEnableOption "soularr container";
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Same Soularr CLI on a qualified minimal Python runtime; prebuild system.build.soularrRuntimeImageContext"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.soularrRuntimeImageRecipe = runtime.dockerfile;
    system.build.soularrRuntimeImageContext = context;
    system.build.soularrRuntimeManifest = manifestSource;
    system.build.soularrRuntimeInputGuard = guardSource;
    systemd.services.podman-soularr.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
      ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
        echo "Prebuild Soularr from ${runtime.dockerfile} before activation" >&2
        exit 1
      }
    '');
    assertions = [
      {
        assertion = config.hwc.media.slskd.enable;
        message = "soularr requires slskd to be enabled";
      }
      {
        assertion = config.hwc.media.lidarr.enable;
        message = "soularr requires lidarr to be enabled";
      }
      {
        assertion = config.age.secrets ? lidarr-api-key && config.age.secrets ? slskd-api-key;
        message = "soularr requires agenix secrets: lidarr-api-key, slskd-api-key";
      }
    ];
  };
}
