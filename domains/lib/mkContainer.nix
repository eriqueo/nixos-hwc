# Application Container Helper
# For standard application containers (media apps, *arr services)
# See mkInfraContainer.nix for infrastructure containers (gluetun, pihole)
#
# =============================================================================
# CONTAINER MODULE STRUCTURE
# =============================================================================
#
# Standard directory layout for container modules:
#
#   domains/media/<app>/
#   ├── index.nix       # Main module: imports, mkIf wrapper, container definition
#   ├── options.nix     # Option declarations (hwc.media.<app>.*)
#   └── parts/          # Optional: max 2 files for complex configs
#       ├── config.nix  # INSIDE: app config generation (YAML/TOML/JSON, templates)
#       └── setup.nix   # OUTSIDE: runtime setup (systemd deps, tmpfiles, firewall)
#
# Guidelines:
#   - Container definition stays in index.nix (it's the main thing the module does)
#   - Use parts/ only when index.nix gets too long (>50 lines of config)
#   - config.nix = what the app needs to know about itself
#   - setup.nix = what NixOS needs to run the app (pre-start, deps, networking)
#   - Multiple home.file or environment.etc entries can live in one parts file
#
# =============================================================================
{ lib, pkgs }:

rec {
  mediaNetworkName = "media-network";
  internalNetworkUnit = name: "init-internal-network-${name}.service";
  # One identity producer for immutable runtime recipes, including callers
  # that qualify shared libraries as well as the Node executable.
  mkRuntimeImage = { name, version, recipe }: {
    inherit recipe;
    image = "localhost/${name}-runtime:${version}-${builtins.substring 0 12 (builtins.hashString "sha256" recipe)}";
    dockerfile = pkgs.writeText "${name}-runtime.Dockerfile" recipe;
  };

  # Preserve an application's bytes while selecting a separately qualified
  # Node executable. Callers own immutable inputs and compatibility evidence.
  mkNodeRuntimeImage =
    { name, appVersion, nodeVersion, upstreamImage, nodeSourceImage }:
    let
      recipe = ''
        FROM ${nodeSourceImage} AS secure-node
        FROM ${upstreamImage}
        COPY --from=secure-node /usr/local/bin/node /usr/local/bin/node
        ENV NODE_VERSION=${nodeVersion}
      '';
    in mkRuntimeImage {
      inherit name recipe;
      version = "${appVersion}-node${nodeVersion}";
    };

  # Temporary CVE-2026-48710 backport of upstream Starlette commit
  # 764dab0dcfb9033d75442d7a359645c9f94648c6. Remove when the upstream
  # app images contain the fix and pass actual URL/FastAPI/GPU checks.
  # Exact before/after hashes fail closed on drift; no dependency resolution.
  mkStarletteHostBackport = { python, version, sourceSha256, patchedSha256 }:
    let program = ''
      import hashlib, importlib, sys
      from pathlib import Path
      import starlette, starlette.datastructures as ds
      version, original, patched = sys.argv[1:]
      p = Path(ds.__file__)
      before = p.read_bytes()
      assert starlette.__version__ == version
      assert hashlib.sha256(before).hexdigest() == original
      source = before.decode()
      old = '            if host_header is not None:'
      assert source.count(old) == 1 and source.count('class URL:') == 1
      pattern = r'^([a-z0-9.-]+|\[[a-f0-9]*:[a-f0-9.:]+\])(?::[0-9]+)?$'
      source = source.replace(old, old[:-1] + ' and _HOST_RE.fullmatch(host_header):')
      source = source.replace('class URL:', 'import re\n_HOST_RE = re.compile(' + repr(pattern) + ', re.IGNORECASE)\n\nclass URL:', 1)
      assert hashlib.sha256(source.encode()).hexdigest() == patched
      p.write_text(source)
      importlib.reload(ds)
      for host in [b'foo/?x=', b'foo/#', b'foo/bar', b'user@foo', b'foo\\bar', b'foo bar']:
          url = ds.URL(scope={'scheme':'http','server':('example.com',80),'path':'/admin','headers':[(b'host',host)]})
          assert url.path == '/admin' and url.netloc == 'example.com'
    '';
    in "RUN ${python} -c ${lib.escapeShellArg ("exec(" + builtins.toJSON program + ")")} ${lib.escapeShellArgs [ version sourceSha256 patchedSha256 ]}\n";

  # Temporary response framing repair. Remove when vendor stdlib and urllib3
  # pass actual Requests streaming/download and normal-response contracts.
  # Both controlled modules share one grammar; no resolver or native changes.
  mkPythonHttpFramingBackport = { python, modules, stdlibUpstreamCommits }:
    let
      manifest = { schemaVersion = 1; inherit modules stdlibUpstreamCommits; };
      program = ''
        import hashlib, itertools, json, subprocess, sys
        from pathlib import Path
        manifest = json.loads(sys.argv[1])
        assert manifest['schemaVersion'] == 1, 'HTTP_BACKPORT_VERSION'
        assert set(manifest['modules']) == {'httpClient', 'urllib3'}, 'HTTP_BACKPORT_PAIR'
        prepared = []
        suffixes = {'httpClient': '/http/client.py', 'urllib3': '/urllib3/response.py'}
        for name, entry in manifest['modules'].items():
            assert set(entry) == {'path', 'sourceSha256', 'patchedSha256', 'replacements'}, 'HTTP_BACKPORT_FIELDS'
            path = Path(entry['path'])
            assert path.is_absolute() and str(path).endswith(suffixes[name]), 'HTTP_MODULE_PATH'
            assert path.stat().st_size <= 262144, 'HTTP_SOURCE_BOUND'
            raw = path.read_bytes()
            assert len(raw) <= 262144, 'HTTP_SOURCE_BOUND'
            assert hashlib.sha256(raw).hexdigest() == entry['sourceSha256'], 'HTTP_SOURCE_DRIFT'
            source = raw.decode()
            assert 1 <= len(entry['replacements']) <= 4, 'HTTP_REPLACEMENT_BOUND'
            for old, new in entry['replacements']:
                assert old and source.count(old) == 1, 'HTTP_HUNK_DRIFT'
                source = source.replace(old, new)
            output = source.encode()
            assert len(output) <= 262144, 'HTTP_RESULT_BOUND'
            assert hashlib.sha256(output).hexdigest() == entry['patchedSha256'], 'HTTP_RESULT_DRIFT'
            compile(source, str(path), 'exec')
            prepared.append((path, output))
        # Validate the complete pair before writing either immutable-image file.
        for path, output in prepared:
            path.write_bytes(output)
            cache = list(itertools.islice((path.parent / '__pycache__').glob(path.stem + '.*.pyc'), 9))
            assert len(cache) <= 8, 'HTTP_BYTECODE_BOUND'
            for entry in cache:
                entry.unlink()
        subprocess.run([sys.executable, '-B', '-c', 'from http.client import _is_legal_content_length, _is_legal_chunk_size; import urllib3.response; assert _is_legal_content_length("5") and not _is_legal_content_length("+5"); assert _is_legal_chunk_size(b"a") and not _is_legal_chunk_size(b"+a")'], check=True, timeout=20)
      '';
    in {
      inherit manifest;
      recipe = "RUN ${lib.escapeShellArg python} -B -c ${lib.escapeShellArg ("exec(" + builtins.toJSON program + ")")} ${lib.escapeShellArg (builtins.toJSON manifest)}\n";
    };

  mkContainer =
    { name
    , image
    , networkMode ? "media"     # "media" | "vpn" | "host" | { kind="named"; names=[...]; }
    , vpnContainer ? "gluetun"  # which tunnel instance "vpn" mode joins
    , gpuEnable ? true
    , gpuMode ? "intel"         # "intel" | "nvidia-cdi" | "nvidia-legacy"
    , timeZone ? "UTC"
    , ports ? []
    , volumes ? []
    , environment ? {}
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    , cmd ? []
    , environmentFiles ? []
    , memory ? "2g"
    , cpus ? "1.0"
    , memorySwap ? "4g"
    , pull ? "missing"          # "always" | "missing" | "never" | "newer"
    }:
    let
      # Network options.
      #
      # "vpn" resolves ONLY to a tunnel netns — there is deliberately no fallback
      # branch here. slskd spent six weeks egressing on the house IP because its
      # network mode said "media" and nothing objected; a container that asks for
      # the tunnel and quietly gets the bridge instead is the same failure with a
      # different spelling. A wrong vpnContainer name must break the container,
      # not silently un-tunnel it. Enforcement that the named instance is real
      # and enabled lives in mkVpnAssertions below, which every VPN-mode module
      # calls.
      podmanNetworkOpts =
        if builtins.isAttrs networkMode then
          let names = networkMode.names or []; in
          assert (networkMode.kind or null) == "named";
          assert builtins.isList names && names != [];
          assert lib.all (name: builtins.isString name && builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" name != null) names;
          assert builtins.length (lib.unique names) == builtins.length names;
          [ "--network=${lib.concatStringsSep "," names}" ]
        else if networkMode == "vpn" then [ "--network=container:${vpnContainer}" ]
        else if networkMode == "host" then [ "--network=host" ]
        else [ "--network=${mediaNetworkName}" ];

      # GPU options based on mode
      gpuOpts =
        if (!gpuEnable) then []
        else if gpuMode == "nvidia-cdi" then [
          # NVIDIA CDI (Container Device Interface) mode - modern approach
          "--device=nvidia.com/gpu=0"
        ]
        else if gpuMode == "nvidia-legacy" then [
          # Legacy NVIDIA passthrough
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ]
        else [
          # Intel/AMD GPU passthrough (default)
          "--device=/dev/dri:/dev/dri"
        ];

      # Base environment (PUID/PGID for linuxserver.io style containers)
      baseEnv = {
        PUID = "1000";  # eric UID
        PGID = "100";   # users GID (CRITICAL - users group is GID 100, not 1000!)
        TZ = timeZone;
      };

      # Resource limits
      resourceOpts = [
        "--memory=${memory}"
        "--cpus=${cpus}"
        "--memory-swap=${memorySwap}"
      ];

      containerDef = {
        inherit image dependsOn pull;
        autoStart = true;
        environment = baseEnv // environment;
        environmentFiles = environmentFiles;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ resourceOpts ++ extraOptions;
        ports = ports;
        volumes = volumes;
      } // lib.optionalAttrs (user != null) { inherit user; }
        // lib.optionalAttrs (cmd != []) { inherit cmd; };

    in {
      virtualisation.oci-containers.containers.${name} = containerDef;
    };

  # Assertions every VPN-mode container needs, produced in one place.
  #
  # These used to be hand-copied into eight modules as
  # `cfg.network.mode != "vpn" || config.hwc.networking.gluetun.enable` — same
  # predicate, eight spellings, and all eight only checked that *a* tunnel
  # existed, not that the one this container joins does. With more than one
  # tunnel that check is worse than none: a container can name a tunnel that was
  # never declared and still pass. Callers pass the live instance set:
  #
  #   mkVpnAssertions {
  #     name = "slskd"; networkMode = cfg.network.mode;
  #     vpnContainer = "gluetun-slskd";
  #     gluetunInstances = config.hwc.networking.gluetun.instances;
  #   }
  mkVpnAssertions =
    { name
    , networkMode
    , vpnContainer ? "gluetun"
    , gluetunInstances
    }:
    lib.optionals (networkMode == "vpn") [
      {
        assertion = gluetunInstances ? ${vpnContainer};
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is not declared in hwc.networking.gluetun.instances";
      }
      {
        assertion = lib.attrByPath [ vpnContainer "enable" ] false gluetunInstances;
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is declared but not enabled";
      }
    ];
}
