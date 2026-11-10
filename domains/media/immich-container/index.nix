# domains/media/immich-container/index.nix
#
# Immich photo management server (containerized)
# Namespace: hwc.media.immich.*

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.immich;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  appVersion = "2.5.6";
  nodeVersion = "24.22.1";
  # Container ABI paths, not host storage paths. Preserve the pinned Python
  # environment and Pillow's audited loader namespace through this correction.
  mlSitePackages = "/opt/venv/lib/python3.11/site-packages";
  pillowLibraries = {
    common = "libbrotlicommon-3ecfe81c.so.1";
    decoder = "libbrotlidec-ba690955.so.1";
  };
  pillowLibraryMode = "0755";
  # Temporary CVE-2026-111497 backport, authenticated through Debian's signed
  # security index. Remove when upstream images pass the same decoder, native
  # consumer and current-data recovery checks without these replacements.
  brotli = rec {
    version = "1.1.0-2+deb13u1";
    upstreamVersion = builtins.head (lib.splitString "-" version);
    filename = "libbrotli1_${version}_amd64.deb";
    url = "https://security.debian.org/debian-security/pool/updates/main/b/brotli/${filename}";
    sha256 = "db46824c60fee46aff3cc0be3e5f736bc606cae669b1fb17516a41e8073251a9";
    source = pkgs.fetchurl { inherit url sha256; };
  };
  # REPLACEABLE: the fixed-hash package plus these loader substitutions rebuild
  # the pair. Only ELF metadata changes; the signed package's code is retained.
  pillowBrotli = pkgs.runCommand "immich-pillow-brotli" {
    nativeBuildInputs = [ pkgs.dpkg pkgs.patchelf ];
  } ''
    dpkg-deb --extract ${brotli.source} extracted
    mkdir -p "$out"
    install -m${pillowLibraryMode} extracted/usr/lib/x86_64-linux-gnu/libbrotlicommon.so.${brotli.upstreamVersion} "$out/${pillowLibraries.common}"
    install -m${pillowLibraryMode} extracted/usr/lib/x86_64-linux-gnu/libbrotlidec.so.${brotli.upstreamVersion} "$out/${pillowLibraries.decoder}"
    patchelf --set-soname ${pillowLibraries.common} "$out/${pillowLibraries.common}"
    patchelf --set-soname ${pillowLibraries.decoder} "$out/${pillowLibraries.decoder}"
    patchelf --replace-needed libbrotlicommon.so.1 ${pillowLibraries.common} "$out/${pillowLibraries.decoder}"
    patchelf --set-rpath '$ORIGIN' "$out/${pillowLibraries.decoder}"
  '';
  # Temporary: preserve the app/schema while qualifying runtime and trust fixes.
  # Remove these derived images when an upstream release passes same-data
  # old/new/old consumers, corrected Node/TLS/root and actual CUDA checks.
  serverNodeRuntime = helpers.mkNodeRuntimeImage {
    name = "immich";
    inherit appVersion nodeVersion;
    upstreamImage = "ghcr.io/immich-app/immich-server@sha256:8b14246ee4c53e39191a54279f8c72f3eed3c026c5b23d0f7e4ab5e69e3aac4a";
    nodeSourceImage = "docker.io/library/node@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205";
  };
  serverRuntime = helpers.mkRuntimeImage {
    name = "immich";
    version = "${appVersion}-node${nodeVersion}";
    recipe = "# Debian Brotli ${brotli.version} sha256:${brotli.sha256}\n" + serverNodeRuntime.recipe + ''
      COPY ${brotli.filename} /tmp/hwc-brotli.deb
      RUN dpkg -i /tmp/hwc-brotli.deb && rm /tmp/hwc-brotli.deb
    '';
  };
  mlBaseImage = "ghcr.io/immich-app/immich-machine-learning@sha256:6bfdbe69ffcd0543f8f8fc45993d9b1559aa3c92078c44b41ece67132d16d9d3";
  certifi = rec {
    version = "2026.10.23";
    filename = "certifi-${version}-py3-none-any.whl";
    sha256 = "e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1";
    url = "https://files.pythonhosted.org/packages/32/d1/a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/${filename}";
  };
  opensslVersion = "3.0.2-0ubuntu1.30"; # Ubuntu USN-8847-1, Jammy backports
  caCertificatesVersion = "20260816ubuntu0.22.04.1";
  # This pinned Ubuntu bundle still trusts these compromised roots after the
  # host's newer NSS bundle has removed them. Keep the legacy-container policy
  # here; an empty host blacklist is not proof about this separate trust store.
  # Remove when the upstream base passes caPolicyCheck without this filter.
  caPolicy = builtins.toJSON [
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];
  caPolicyScript = "from pathlib import Path; import json,sys; p=Path('/etc/ca-certificates.conf'); blocked={'mozilla/'+n.replace(' ','_')+'.crt' for n in json.loads(sys.argv[1])}; p.write_text(''.join('!'+l if l.strip() in blocked else l for l in p.read_text().splitlines(True)))";
  caPolicyCheck = "import ssl,json,sys,certifi; blocked=set(json.loads(sys.argv[1])); roots=lambda p:{v for c in ssl.create_default_context(cafile=p).get_ca_certs() for row in c['subject'] for k,v in row if k=='commonName'}; assert all(not roots(p)&blocked for p in [certifi.where(),'/etc/ssl/certs/ca-certificates.crt']), 'blocked root remains trusted'";
  mlBaseRuntimeRecipe = "# Pillow Brotli ${pillowBrotli} sha256:${brotli.sha256}\n" + ''
    FROM ${mlBaseImage} AS certifi-builder
    ADD --checksum=sha256:${certifi.sha256} ${certifi.url} /tmp/${certifi.filename}
    RUN /opt/venv/bin/python -m ensurepip && /opt/venv/bin/python -m pip install --no-index --no-deps --force-reinstall /tmp/${certifi.filename}
    FROM ${mlBaseImage}
    RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --only-upgrade -y libssl3=${opensslVersion} openssl=${opensslVersion} ca-certificates=${caCertificatesVersion} && apt-get clean && rm -rf /var/lib/apt/lists/* ${mlSitePackages}/certifi ${mlSitePackages}/certifi-2025.11.12.dist-info
    COPY --from=certifi-builder ${mlSitePackages}/certifi ${mlSitePackages}/certifi
    COPY --from=certifi-builder ${mlSitePackages}/certifi-${certifi.version}.dist-info ${mlSitePackages}/certifi-${certifi.version}.dist-info
    RUN /opt/venv/bin/python -c ${lib.escapeShellArg caPolicyScript} ${lib.escapeShellArg caPolicy} && update-ca-certificates --fresh
    RUN /opt/venv/bin/python -c ${lib.escapeShellArg caPolicyCheck} ${lib.escapeShellArg caPolicy}
    COPY pillow-brotli/ ${mlSitePackages}/pillow.libs/
    RUN chmod ${pillowLibraryMode} ${mlSitePackages}/pillow.libs/${pillowLibraries.common} ${mlSitePackages}/pillow.libs/${pillowLibraries.decoder}
  '' + helpers.mkStarletteHostBackport {
    python = "/opt/venv/bin/python";
    version = "0.50.0";
    sourceSha256 = "dde752330006431c7ebc1ccb948a95825be5bd6b8c03839133cdee59899c3030";
    patchedSha256 = "77253c43dce33af8b92b1b76794c6b39205419a520663246dfba595e4c76b283";
  };
  mlBaseRuntime = helpers.mkRuntimeImage {
    name = "immich-ml";
    version = appVersion;
    recipe = mlBaseRuntimeRecipe;
  };
  # Temporary: these vendor HTTP fixes and strict framing preserve the frozen
  # app/native graph. Retire after the upstream ML image passes these consumers.
  httpWheels = {
    requests = {
      originalVersion = "2.32.4";
      version = "2.33.0";
      filename = "requests-2.33.0-py3-none-any.whl";
      url = "https://files.pythonhosted.org/packages/56/5d/c814546c2333ceea4ba42262d8c4d55763003e767fa169adc693bd524478/requests-2.33.0-py3-none-any.whl";
      sha256 = "3324635456fa185245e24865e810cecec7b4caf933d7eb133dcde67d48cee69b";
    };
    urllib3 = {
      originalVersion = "2.6.2";
      version = "2.8.0";
      filename = "urllib3-2.8.0-py3-none-any.whl";
      url = "https://files.pythonhosted.org/packages/92/9d/c4e665119135114480843e7ab388fa94d8480650450e6f8e26b70d323a4c/urllib3-2.8.0-py3-none-any.whl";
      sha256 = "0cf3cae568d36aa9576b28dfb35f11328f1cb974ca7647d9475ebb86c75ac6e3";
    };
  };
  httpBackport = helpers.mkPythonHttpFramingBackport {
    python = "/opt/venv/bin/python";
    stdlibUpstreamCommits = pkgs.pythonHttpFramingBackport.upstreamCommits;
    modules = {
      httpClient = {
        path = "/usr/local/lib/python3.11/http/client.py";
        sourceSha256 = "c3968eae8a9f38b0026e9b0ae0d2396b5fb3ade65688a17ed0ffeb4d7d9630f6";
        patchedSha256 = "18395a51c62e28c81855f6b847c1a62f1e484ab587ea754931bcefe9d626fe58";
        replacements = pkgs.pythonHttpFramingBackport.replacements;
      };
      urllib3 = {
        path = "${mlSitePackages}/urllib3/response.py";
        inherit (pkgs.pythonUrllib3FramingBackport.sources.${httpWheels.urllib3.version}) sourceSha256 patchedSha256;
        replacements = pkgs.pythonUrllib3FramingBackport.replacements;
      };
    };
  };
  httpManifest = {
    schemaVersion = 1;
    sitePackages = mlSitePackages;
    wheelDirectory = "/tmp/hwc-http";
    wheels = httpWheels;
    baseImage = mlBaseRuntime.image;
    framing = httpBackport.manifest;
  };
  # All archive and installed-owner guards precede writes in this private image
  # layer. Install pure wheels directly; no dependency resolver or native build.
  installHttpWheels = ''
    import hashlib, importlib.metadata, json, shutil, stat, sys, zipfile
    from pathlib import Path
    spec = json.loads(sys.argv[1])
    assert spec['schemaVersion'] == 1, 'ML_HTTP_VERSION'
    root = Path(spec['sitePackages'])
    assert root.is_absolute(), 'ML_HTTP_SITE_PATH'
    prepared = []
    for name, entry in spec['wheels'].items():
        assert name in {'requests', 'urllib3'}, 'ML_HTTP_PACKAGE_OWNER'
        installed = importlib.metadata.distribution(name)
        assert installed.version == entry['originalVersion'], 'ML_HTTP_INSTALLED_VERSION'
        assert Path(installed.locate_file("")) == root, 'ML_HTTP_INSTALLED_PATH'
        old_info = name + '-' + entry['originalVersion'] + '.dist-info'
        new_info = name + '-' + entry['version'] + '.dist-info'
        assert (root / name).is_dir() and (root / old_info).is_dir() and not (root / new_info).exists(), 'ML_HTTP_INSTALLED_OWNER'
        assert all(Path(f).parts[0] in {name, old_info} and '..' not in Path(f).parts for f in installed.files), 'ML_HTTP_INSTALLED_RECORD'
        wheel = Path(spec['wheelDirectory']) / entry['filename']
        assert wheel.stat().st_size <= 1048576, 'ML_HTTP_WHEEL_BOUND'
        raw = wheel.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256'], 'ML_HTTP_WHEEL_DRIFT'
        with zipfile.ZipFile(wheel) as archive:
            members = archive.infolist()
            assert len(members) <= 128 and sum(x.file_size for x in members) <= 2097152, 'ML_HTTP_ARCHIVE_BOUND'
            outputs = []
            for member in members:
                rel = Path(member.filename)
                assert not rel.is_absolute() and '..' not in rel.parts and rel.parts[0] in {name, new_info}, 'ML_HTTP_ARCHIVE_PATH'
                if member.is_dir():
                    continue
                mode = member.external_attr >> 16
                # ZIP may carry permission bits without Unix file-type bits.
                # Accept that regular-file convention; reject links/devices.
                assert stat.S_IFMT(mode) in {0, stat.S_IFREG}, 'ML_HTTP_ARCHIVE_TYPE'
                outputs.append((rel, archive.read(member)))
            assert outputs and any(str(p) == new_info + '/METADATA' for p, _ in outputs), 'ML_HTTP_ARCHIVE_METADATA'
        prepared.append((name, old_info, outputs))
    assert {name for name, _, _ in prepared} == {'requests', 'urllib3'}, 'ML_HTTP_PACKAGE_PAIR'
    for name, old_info, outputs in prepared:
        shutil.rmtree(root / name)
        shutil.rmtree(root / old_info)
        for relative, raw in outputs:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            path.chmod(0o644)
  '';
  httpInstallCommand = "import sys; sys.argv = ['hwc-ml-http', "
    + builtins.toJSON (builtins.toJSON httpManifest) + "]; exec(compile("
    + builtins.toJSON installHttpWheels + ", '<ml-http-wheels>', 'exec', optimize=0), {'__name__':'__main__'})";
  mlRuntimeRecipe = ''
    FROM ${mlBaseRuntime.image}
    COPY wheels/ /tmp/hwc-http/
    RUN /opt/venv/bin/python -B -c ${lib.escapeShellArg httpInstallCommand}
  '' + httpBackport.recipe + "RUN rm -rf /tmp/hwc-http\n";
  mlRuntimeImage = "localhost/immich-ml-runtime:${appVersion}-${builtins.substring 0 12 (builtins.hashString "sha256" mlRuntimeRecipe)}";
  securityManifest = pkgs.writeText "immich-runtime-security.json" (builtins.toJSON {
    schemaVersion = 1;
    brotli = { inherit (brotli) version filename url sha256; };
    inherit pillowLibraries pillowLibraryMode;
  });
  # REPLACEABLE contexts; startup consumes prebuilt images only. Existing ML
  # TLS/CA layers still use their pinned network inputs on an uncached build.
  serverContext = pkgs.runCommand "immich-server-runtime-context" {} ''
    mkdir -p "$out"
    cp ${serverRuntime.dockerfile} "$out/Dockerfile"
    cp ${securityManifest} "$out/manifest.json"
    cp ${brotli.source} "$out/${brotli.filename}"
  '';
  mlBaseContext = pkgs.runCommand "immich-ml-runtime-context" {} ''
    mkdir -p "$out/pillow-brotli"
    cp ${mlBaseRuntime.dockerfile} "$out/Dockerfile"
    cp ${securityManifest} "$out/manifest.json"
    cp -p ${pillowBrotli}/* "$out/pillow-brotli/"
  '';
  mlContext = pkgs.runCommand "immich-ml-http-runtime-context" {} ''
    mkdir -p "$out/wheels"
    cp ${pkgs.writeText "immich-ml-runtime.Dockerfile" mlRuntimeRecipe} "$out/Dockerfile"
    cp ${pkgs.writeText "immich-ml-http.json" (builtins.toJSON httpManifest)} "$out/manifest.json"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (_: entry:
      "cp ${pkgs.fetchurl { inherit (entry) url sha256; }} \"$out/wheels/${entry.filename}\"") httpWheels)}
  '';
in
{
  imports = [
    ./parts/config.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.immich = {
    enable = lib.mkEnableOption "Immich photo management server (containerized)";

    images = {
      server = lib.mkOption { type = lib.types.str; default = serverRuntime.image; description = "Qualified same-app Node/shared-library image; build system.build.immichServerRuntimeImageContext"; };
      machineLearning = lib.mkOption { type = lib.types.str; default = mlRuntimeImage; description = "Qualified same-app TLS/CA/Pillow image; build system.build.immichMlRuntimeImageContext"; };
      redis = lib.mkOption { type = lib.types.str; default = "docker.io/library/redis:7.2-alpine"; description = "Redis container image"; };
    };

    settings = {
      host = lib.mkOption { type = lib.types.str; default = "0.0.0.0"; description = "Listen address for Immich server"; };
      port = lib.mkOption { type = lib.types.port; default = 2283; description = "Port for Immich server"; };
      mediaLocation = lib.mkOption { type = lib.types.nullOr lib.types.path; default = config.hwc.paths.photos; description = "Path to media storage location"; };
    };

    storage = {
      enable = lib.mkEnableOption "Advanced storage layout with separate directories" // { default = true; };
      basePath = lib.mkOption { type = lib.types.nullOr lib.types.path; default = config.hwc.paths.photos; description = "Base path for all Immich storage"; };
      locations = {
        library = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/library" else null; description = "Primary photo/video library location"; };
        thumbs = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/thumbs" else null; description = "Thumbnail cache location"; };
        encodedVideo = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/encoded-video" else null; description = "Transcoded video storage"; };
        profile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/profile" else null; description = "User profile pictures"; };
      };
    };

    database = {
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "PostgreSQL host"; };
      port = lib.mkOption { type = lib.types.port; default = 5432; description = "PostgreSQL port"; };
      name = lib.mkOption { type = lib.types.str; default = "immich"; description = "Database name"; };
      user = lib.mkOption { type = lib.types.str; default = "immich"; description = "Database user"; };
      passwordSecret = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Generated agenix secret for a restricted database role; enables managed role provisioning."; };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if cfg.database.passwordSecret == null then null
          else config.hwc.secrets.api.${cfg.database.passwordSecret};
        description = "Protected password path consumed by the vendor DB_PASSWORD_FILE loader.";
      };
    };

    redis = {
      enable = lib.mkEnableOption "Redis caching for Immich" // { default = true; };
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Redis host"; };
      port = lib.mkOption { type = lib.types.port; default = 6379; description = "Redis port"; };
    };

    gpu.enable = lib.mkEnableOption "GPU acceleration for photo/video processing";

    observability = {
      logLevel = lib.mkOption { type = lib.types.enum [ "verbose" "debug" "log" "warn" "error" ]; default = "log"; description = "Immich log level"; };
      metrics = {
        enable = lib.mkEnableOption "Prometheus metrics endpoints" // { default = true; };
        apiPort = lib.mkOption { type = lib.types.port; default = 8091; description = "Prometheus metrics port for immich-server"; };
        microservicesPort = lib.mkOption { type = lib.types.port; default = 8092; description = "Prometheus metrics port for ML"; };
      };
    };

    machineLearning = {
      enable = lib.mkEnableOption "Immich machine learning container" // { default = true; };
      cpuCores = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Number of CPU cores for ML threading"; };
      modelTTL = lib.mkOption { type = lib.types.int; default = 600; description = "Time-to-live for ML models in GPU memory (seconds)"; };
      modelTTLPollInterval = lib.mkOption { type = lib.types.int; default = 30; description = "How often to check if models should be unloaded (seconds)"; };
      threading = {
        requestThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Concurrent ML requests to process"; };
        interOpThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Inter-op parallelism for ML models"; };
        intraOpThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Intra-op parallelism for ML models"; };
      };
    };

    reverseProxy.trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "CIDR ranges of trusted reverse proxies"; };

    network.mode = lib.mkOption { type = lib.types.enum [ "media" "host" ]; default = "media"; description = "Network mode: media (podman network) or host"; };

    resources = {
      server = {
        memory = lib.mkOption { type = lib.types.str; default = "2g"; description = "Memory limit for immich-server"; };
        cpus = lib.mkOption { type = lib.types.str; default = "2.0"; description = "CPU limit for immich-server"; };
      };
      machineLearning = {
        memory = lib.mkOption { type = lib.types.str; default = "4g"; description = "Memory limit for immich-machine-learning"; };
        cpus = lib.mkOption { type = lib.types.str; default = "4.0"; description = "CPU limit for immich-machine-learning"; };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.immichServerRuntimeImageRecipe = serverRuntime.dockerfile;
    system.build.immichMlRuntimeImageRecipe = pkgs.writeText "immich-ml-runtime.Dockerfile" mlRuntimeRecipe;
    system.build.immichServerRuntimeImageContext = serverContext;
    system.build.immichMlRuntimeImageContext = mlContext;
    system.build.immichMlBaseRuntimeImageRecipe = mlBaseRuntime.dockerfile;
    system.build.immichMlBaseRuntimeImageContext = mlBaseContext;
    system.build.immichPillowBrotliLibraries = pillowBrotli;
    system.build.immichRuntimeSecurityManifest = securityManifest;
    # HWC-EXCEPTION(Law 5): mkContainer in parts/config.nix still owns each
    # container. These overrides only require its exact prebuilt local image.
    # Remove with the temporary runtime recipes after upstream qualification.
    virtualisation.oci-containers.containers = lib.mkMerge [
      (lib.mkIf (cfg.images.server == serverRuntime.image) {
        immich-server.pull = lib.mkForce "never";
      })
      (lib.mkIf (cfg.images.machineLearning == mlRuntimeImage) {
        immich-machine-learning.pull = lib.mkForce "never";
      })
    ];
    systemd.services = lib.mkMerge [
      (lib.mkIf (cfg.images.server == serverRuntime.image) {
        podman-immich-server.preStart = lib.mkBefore ''
          ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg serverRuntime.image} || {
            echo "Immich requires the reviewed image from ${serverContext} before startup" >&2
            exit 1
          }
        '';
      })
      (lib.mkIf (cfg.images.machineLearning == mlRuntimeImage) {
        podman-immich-machine-learning.preStart = lib.mkBefore ''
          ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg mlRuntimeImage} || {
            echo "Immich ML requires the reviewed image from ${mlContext} before startup" >&2
            exit 1
          }
        '';
      })
    ];
  };
}
