{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.calibre;
  paths = config.hwc.paths;
  calibrePython = "/opt/calibre/calibre-debug";
  httpSourceSha256 = "016aa7664201a82f0f37ddfb11ed662dd1f07aa23c9470c6a3cb3278aa479230";
  httpSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/python/cpython/v3.14.8/Lib/http/client.py";
    sha256 = httpSourceSha256;
  };
  httpBackport = helpers.mkFrozenPythonHttpFramingBackport {
    python = calibrePython;
    pythonVersion = [ 3 14 8 ];
    frozenBundle = "/opt/calibre/lib/calibre-extensions/python-lib.bypy.frozen";
    frozenBundleSha256 = "558037f93bef7df037ff1c38519680ed1083263b9e86b38407c4e819a2acffb2";
    sourcePath = "/tmp/hwc-calibre-http/client.py";
    sourceSha256 = httpSourceSha256;
    rootPath = "/opt/hwc-calibre-http";
    selectionVariable = "CALIBRE_DEVELOP_FROM";
    environment = {
      CALIBRE_CONFIG_DIRECTORY = "/tmp/hwc-frozen-config";
      XDG_CACHE_HOME = "/tmp/hwc-frozen-cache";
    };
    consumerVerification = ''
      import calibre.gui2
      from calibre.constants import is_running_from_develop
      from calibre.utils.ipc.simple_worker import fork_job
      assert not is_running_from_develop, 'CALIBRE_GUI_DEVELOP_MODE'
      worker = "def prove():\n import http.client\n from calibre.constants import is_running_from_develop\n return (is_running_from_develop,http.client.__file__,bool(http.client._is_legal_chunk_size(b'a')),bool(http.client._is_legal_chunk_size(b'+a')))\n"
      actual = fork_job(worker, 'prove', timeout=15, no_output=True, module_is_source_code=True)['result']
      assert actual == (False, str(path), True, False), 'CALIBRE_WORKER_HTTP_SELECTION'
    '';
  };
  # Temporary: the vendor FFmpeg 7.1.2 predates same-ABI security fixes.
  # Retire when the unmodified vendor eight-library group passes this contract.
  nativeFfmpeg = (pkgs.ffmpeg_7.override {
    withHeadlessDeps = false; withSmallDeps = false; withFullDeps = false;
    withBzlib = true; withIconv = true; withZlib = true; withNetwork = true;
    withVersion3 = false;
    buildAvcodec = true; buildAvdevice = true; buildAvfilter = true;
    buildAvformat = true; buildAvutil = true; buildPostproc = true;
    buildSwresample = true; buildSwscale = true;
    withSafeBitstreamReader = true; withPixelutils = true;
    withAlsa = true; withDrm = true;
    withXcbShape = true; withXcbShm = true; withXcbxfixes = true;
    libiconv = pkgs.libiconvReal;
  }).overrideAttrs (old: {
    configureFlags = old.configureFlags ++ [ "--disable-decoder=truemotion1" ];
  });
  # Measured canonical 9.17 source group. All filename, role and dependency
  # consumers derive from this one table, including the portable ELF allowlist.
  nativeLibraries = builtins.fromJSON ''
    {
      "libavcodec.so.61": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libiconv.so.2",
          "libm.so.6",
          "libswresample.so.5",
          "libz.so.1"
        ],
        "role": "codec",
        "sourceMode": 493,
        "sourceSha256": "bc1351458e87140e8e8c82f143961c0dbe80c5b6be6248859f18bc9dc8852498"
      },
      "libavdevice.so.61": {
        "needed": [
          "libasound.so.2",
          "libavcodec.so.61",
          "libavfilter.so.10",
          "libavformat.so.61",
          "libavutil.so.59",
          "libc.so.6",
          "libdrm.so.2",
          "libxcb-shape.so.0",
          "libxcb-shm.so.0",
          "libxcb-xfixes.so.0",
          "libxcb.so.1"
        ],
        "role": "device",
        "sourceMode": 493,
        "sourceSha256": "b1a097abf6d0cdd462de245355b258f919728db0b162cd685bdf5485190145b1"
      },
      "libavfilter.so.10": {
        "needed": [
          "libavcodec.so.61",
          "libavformat.so.61",
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6",
          "libpostproc.so.58",
          "libswresample.so.5",
          "libswscale.so.8"
        ],
        "role": "filter",
        "sourceMode": 493,
        "sourceSha256": "7dc5981e1922a22a204b43a63e1bf7ce4531bb01439260f6a5617d15cdff917d"
      },
      "libavformat.so.61": {
        "needed": [
          "libavcodec.so.61",
          "libavutil.so.59",
          "libbz2.so.1.0",
          "libc.so.6",
          "libiconv.so.2",
          "libm.so.6",
          "libz.so.1"
        ],
        "role": "format",
        "sourceMode": 493,
        "sourceSha256": "0b5b15a9d4a63ef8b40dfcb55b1b8a7b6e62baec7aa0a0224e458e32b7802aa4"
      },
      "libavutil.so.59": {
        "needed": [
          "libc.so.6",
          "libdrm.so.2",
          "libm.so.6"
        ],
        "role": "util",
        "sourceMode": 493,
        "sourceSha256": "d9209d6432ba742251c1bbbc3765ce20fe2ae08dd4dcc45a52fdef9d1f0a329d"
      },
      "libpostproc.so.58": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6"
        ],
        "role": "postproc",
        "sourceMode": 493,
        "sourceSha256": "c43c3c4e7ad19f84d902274f41407a88ca57d0f13c351a7539a51bd658ec2539"
      },
      "libswresample.so.5": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6"
        ],
        "role": "resample",
        "sourceMode": 493,
        "sourceSha256": "dd478a3977a74d63e5579738de03c23c6955469f3c3c90dd10a1efbbf438ed57"
      },
      "libswscale.so.8": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6"
        ],
        "role": "scale",
        "sourceMode": 493,
        "sourceSha256": "00e7c791fbeac65fe133f61f4ff16aa5f184400cf38e0907399d9faeffefd7af"
      }
    }
  '';
  nativeDependencies = lib.unique (lib.concatMap (entry: entry.needed) (builtins.attrValues nativeLibraries));
  nativeDescriptor = {
    schemaVersion = 1;
    sourceVersion = "7.1.2";
    version = nativeFfmpeg.version;
    minimumVersion = "7.1.5";
    families = nativeFfmpeg.meta.pkgConfigModules;
    libraries = nativeLibraries;
    # Nix and the vendor use different names for the same bzip2 ABI. The
    # required BZ2 exports exist in the retained bundled library. No bytes
    # outside FFmpeg change. Permanent by design for this transport pair.
    dependencyAliases."libbz2.so.1" = builtins.head (builtins.filter
      (name: lib.hasPrefix "libbz2.so." name) nativeDependencies);
    # These paths describe input identity inside JSON; they are not a closure
    # to install in the container. nativeBundle holds the real build edges.
    sourceInput = builtins.unsafeDiscardStringContext (toString nativeFfmpeg.src);
    libraryInput = builtins.unsafeDiscardStringContext (toString nativeFfmpeg.lib);
    commands = { verify = "verify"; apply = "apply"; installed = "installed"; features = "features"; };
    snapshotFile = "original-features.json";
    limits = {
      fileBytes = 67108864; groupBytes = 134217728;
      manifestBytes = 1048576; featuresBytes = 1048576;
      entries = 2048; nameBytes = 256; probeSeconds = 20;
    };
  };
  nativeSpec = pkgs.writeText "calibre-native-spec.json" (builtins.toJSON nativeDescriptor);
  nativeGuard = pkgs.writeText "calibre-native-guard.py" ''
    import ctypes
    import hashlib
    import json
    import os
    from pathlib import Path
    import shutil
    import stat
    import subprocess
    import sys


    def digest(raw):
        return hashlib.sha256(raw).hexdigest()


    def canonical(value):
        return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


    def file_hash(path, limit):
        identity = path.lstat()
        assert stat.S_ISREG(identity.st_mode) and identity.st_size <= limit, "CALIBRE_NATIVE_FILE_TYPE_BOUND"
        with path.open("rb") as handle:
            return hashlib.file_digest(handle, "sha256").hexdigest()


    def schema(spec, manifest):
        assert spec["schemaVersion"] == manifest["schemaVersion"] == 1, "CALIBRE_NATIVE_SCHEMA"
        assert manifest["descriptor"] == spec, "CALIBRE_NATIVE_DESCRIPTOR"
        libraries = spec["libraries"]
        assert libraries and set(manifest["files"]) == set(libraries), "CALIBRE_NATIVE_SET"
        assert {name.split(".so.")[0] for name in libraries} == set(spec["families"]), "CALIBRE_NATIVE_FAMILIES"
        assert len({item["role"] for item in libraries.values()}) == len(libraries), "CALIBRE_NATIVE_ROLES"
        assert len(set(spec["commands"].values())) == len(spec["commands"]), "CALIBRE_NATIVE_COMMANDS"
        assert Path(spec["snapshotFile"]).name == spec["snapshotFile"] and spec["snapshotFile"].endswith(".json"), "CALIBRE_NATIVE_SNAPSHOT_PATH"
        source_version = tuple(map(int, spec["sourceVersion"].split(".")))
        target_version = tuple(map(int, spec["version"].split(".")))
        minimum = tuple(map(int, spec["minimumVersion"].split(".")))
        assert len(source_version) == len(target_version) == len(minimum) == 3, "CALIBRE_NATIVE_VERSION_TYPE"
        assert source_version[0] == target_version[0] and target_version >= minimum, "CALIBRE_NATIVE_VERSION"
        allowed = {needed for entry in libraries.values() for needed in entry["needed"]}
        assert all(old != new and new in allowed for old, new in spec["dependencyAliases"].items()), "CALIBRE_NATIVE_DEPENDENCY_ALIAS"
        for name, entry in manifest["files"].items():
            assert Path(name).name == name and ".so." in name, "CALIBRE_NATIVE_PATH"
            assert entry["soname"] == name and entry["rpath"] == "$ORIGIN", "CALIBRE_NATIVE_ABI_RPATH"
            assert set(entry["needed"]) <= allowed, "CALIBRE_NATIVE_DEPENDENCY"
            assert 0 < entry["bytes"] <= spec["limits"]["fileBytes"], "CALIBRE_NATIVE_FILE_BOUND"


    def package(spec, directory):
        path = directory / "manifest.json"
        assert stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size <= spec["limits"]["manifestBytes"], "CALIBRE_NATIVE_MANIFEST_BOUND"
        manifest = json.loads(path.read_text())
        schema(spec, manifest)
        root = directory / "lib"
        assert root.is_dir() and not root.is_symlink(), "CALIBRE_NATIVE_PACKAGE_ROOT"
        assert {path.name for path in root.iterdir()} == set(spec["libraries"]), "CALIBRE_NATIVE_PACKAGE_SET"
        used = 0
        for name, entry in manifest["files"].items():
            path = root / name
            assert path.stat().st_size == entry["bytes"], "CALIBRE_NATIVE_INPUT_SIZE"
            used += entry["bytes"]
            assert used <= spec["limits"]["groupBytes"], "CALIBRE_NATIVE_GROUP_BOUND"
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sha256"], "CALIBRE_NATIVE_INPUT_HASH"
        return manifest


    def source(spec, root):
        assert root.is_dir() and not root.is_symlink(), "CALIBRE_NATIVE_SOURCE_ROOT"
        for name, entry in spec["libraries"].items():
            path = root / name
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sourceSha256"], "CALIBRE_NATIVE_SOURCE_HASH"
            assert stat.S_IMODE(path.stat().st_mode) == entry["sourceMode"], "CALIBRE_NATIVE_SOURCE_MODE"


    def verify_inputs(spec, directory, root):
        manifest = package(spec, directory)
        source(spec, root)
        return manifest


    def target_features(spec, original, candidate):
        assert original["version"] == spec["sourceVersion"], "CALIBRE_NATIVE_ORIGINAL_VERSION"
        assert candidate["version"] == spec["version"], "CALIBRE_NATIVE_SELECTED_VERSION"
        assert original["features"].keys() == candidate["features"].keys(), "CALIBRE_NATIVE_FEATURE_GROUP"
        for kind, names in original["features"].items():
            assert set(names) <= set(candidate["features"][kind]), "CALIBRE_NATIVE_FEATURE_LOST:" + kind


    def installed_hashes(spec, manifest, root):
        for name, entry in manifest["files"].items():
            path = root / name
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sha256"], "CALIBRE_NATIVE_INSTALLED_HASH"
            assert stat.S_IMODE(path.stat().st_mode) == spec["libraries"][name]["sourceMode"], "CALIBRE_NATIVE_INSTALLED_MODE"


    def apply(spec, directory, root, feature_reader):
        # Verify both complete groups and native feature/loader compatibility before
        # touching an installed library. A failed RUN discards this private layer.
        manifest = verify_inputs(spec, directory, root)
        original = feature_reader(root)
        candidate = feature_reader(directory / "lib")
        target_features(spec, original, candidate)
        snapshot = {"schemaVersion": 1, "descriptorSha256": digest(canonical(spec)),
                    "manifestSha256": digest(canonical(manifest)), "original": original}
        raw = canonical(snapshot)
        assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_SNAPSHOT_BOUND"
        (directory / spec["snapshotFile"]).write_bytes(raw)
        for name in spec["libraries"]:
            shutil.copyfile(directory / "lib" / name, root / name)
            os.chmod(root / name, spec["libraries"][name]["sourceMode"])
        installed_hashes(spec, manifest, root)
        target_features(spec, original, feature_reader(root))


    def verify_installed(spec, directory, root, feature_reader):
        manifest = package(spec, directory)
        installed_hashes(spec, manifest, root)
        path = directory / spec["snapshotFile"]
        assert stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_SNAPSHOT_BOUND"
        snapshot = json.loads(path.read_text())
        assert snapshot["schemaVersion"] == 1, "CALIBRE_NATIVE_SNAPSHOT_SCHEMA"
        assert snapshot["descriptorSha256"] == digest(canonical(spec)), "CALIBRE_NATIVE_SNAPSHOT_DESCRIPTOR"
        assert snapshot["manifestSha256"] == digest(canonical(manifest)), "CALIBRE_NATIVE_SNAPSHOT_MANIFEST"
        target_features(spec, snapshot["original"], feature_reader(root))


    class Named(ctypes.Structure):
        _fields_ = [("name", ctypes.c_char_p)]


    def dependency_order(metadata):
        pending, result = set(metadata), []
        while pending:
            ready = sorted(name for name in pending if not (set(metadata[name]["needed"]) & pending))
            assert ready, "CALIBRE_NATIVE_DEPENDENCY_CYCLE"
            result.extend(ready)
            pending.difference_update(ready)
        return result


    def features(spec, manifest, root, dependency_root):
        # This runs in a fresh child. Never mix old and new equal SONAMEs in one
        # loader namespace, or select a version from a library already in memory.
        actual = {name: file_hash(root / name, spec["limits"]["fileBytes"]) for name in spec["libraries"]}
        old = {name: value["sourceSha256"] for name, value in spec["libraries"].items()}
        new = {name: value["sha256"] for name, value in manifest["files"].items()}
        assert actual in [old, new], "CALIBRE_NATIVE_UNQUALIFIED_GROUP"
        metadata = spec["libraries"] if actual == old else manifest["files"]
        needed = {name for entry in metadata.values() for name in entry["needed"]}
        for name in sorted(needed - set(metadata)):
            path = dependency_root / name
            if path.is_file():
                assert not path.is_symlink(), "CALIBRE_NATIVE_DEPENDENCY_LINK"
                ctypes.CDLL(str(path), mode=ctypes.RTLD_GLOBAL)
        loaded = {}
        for name in dependency_order(metadata):
            loaded[name] = ctypes.CDLL(str(root / name), mode=ctypes.RTLD_GLOBAL)
        roles = {entry["role"]: loaded[name] for name, entry in spec["libraries"].items()}
        codec, fmt, filters, util, device = (roles[name] for name in ["codec", "format", "filter", "util", "device"])
        device.avdevice_register_all.argtypes = []
        device.avdevice_register_all.restype = None
        device.avdevice_register_all()
        def named(library, method):
            function = getattr(library, method)
            function.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
            function.restype = ctypes.POINTER(Named)
            opaque, rows = ctypes.c_void_p(), []
            for _ in range(spec["limits"]["entries"]):
                entry = function(ctypes.byref(opaque))
                if not entry:
                    return rows
                value = entry.contents.name
                assert len(value) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
                rows.append((value.decode("ascii"), ctypes.cast(entry, ctypes.c_void_p)))
            raise AssertionError("CALIBRE_NATIVE_ENUMERATION_BOUND")
        for method in ["av_codec_is_decoder", "av_codec_is_encoder"]:
            function = getattr(codec, method)
            function.argtypes, function.restype = [ctypes.c_void_p], ctypes.c_int
        entries = named(codec, "av_codec_iterate")
        values = {
            "decoders": sorted({name for name, pointer in entries if codec.av_codec_is_decoder(pointer)}),
            "encoders": sorted({name for name, pointer in entries if codec.av_codec_is_encoder(pointer)}),
            "demuxers": sorted({alias for name, _ in named(fmt, "av_demuxer_iterate") for alias in name.split(",")}),
            "muxers": sorted({alias for name, _ in named(fmt, "av_muxer_iterate") for alias in name.split(",")}),
            "filters": sorted({name for name, _ in named(filters, "av_filter_iterate")}),
        }
        fmt.avio_enum_protocols.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int]
        fmt.avio_enum_protocols.restype = ctypes.c_char_p
        for output, kind in enumerate(["inputProtocols", "outputProtocols"]):
            opaque, rows = ctypes.c_void_p(), []
            for _ in range(spec["limits"]["entries"]):
                name = fmt.avio_enum_protocols(ctypes.byref(opaque), output)
                if not name:
                    break
                assert len(name) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
                rows.append(name.decode("ascii"))
            else:
                raise AssertionError("CALIBRE_NATIVE_PROTOCOL_BOUND")
            values[kind] = sorted(set(rows))
        util.av_hwdevice_iterate_types.argtypes, util.av_hwdevice_iterate_types.restype = [ctypes.c_int], ctypes.c_int
        util.av_hwdevice_get_type_name.argtypes, util.av_hwdevice_get_type_name.restype = [ctypes.c_int], ctypes.c_char_p
        hardware, kind = [], 0
        for _ in range(spec["limits"]["entries"]):
            kind = util.av_hwdevice_iterate_types(kind)
            if not kind:
                break
            name = util.av_hwdevice_get_type_name(kind)
            assert len(name) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
            hardware.append(name.decode("ascii"))
        else:
            raise AssertionError("CALIBRE_NATIVE_HARDWARE_BOUND")
        values["hardwareDeviceTypes"] = sorted(set(hardware))
        util.av_version_info.restype = ctypes.c_char_p
        return {"version": util.av_version_info().decode("ascii"), "features": values}


    if __name__ == "__main__":
        try:
            if sys.flags.optimize:
                raise AssertionError("CALIBRE_NATIVE_OPTIMIZED_GUARD")
            mode, spec_file, directory, root, dependency_root = sys.argv[1:]
            spec_file, directory, root, dependency_root = map(Path, [spec_file, directory, root, dependency_root])
            assert spec_file.stat().st_size <= 65536, "CALIBRE_NATIVE_SPEC_BOUND"
            spec = json.loads(spec_file.read_text())
            manifest = package(spec, directory)
            commands = spec["commands"]
            assert mode in commands.values(), "CALIBRE_NATIVE_COMMAND"
            def read_features(path):
                raw = subprocess.check_output([sys.executable, "-B", str(Path(__file__).resolve()), commands["features"],
                    str(spec_file), str(directory), str(path), str(dependency_root)], timeout=spec["limits"]["probeSeconds"])
                assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_FEATURE_BOUND"
                return json.loads(raw)
            if mode == commands["features"]:
                result = features(spec, manifest, root, dependency_root)
                raw = canonical(result)
                assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_FEATURE_BOUND"
                print(raw.decode())
            elif mode == commands["verify"]:
                verify_inputs(spec, directory, root)
            elif mode == commands["apply"]:
                apply(spec, directory, root, read_features)
            else:
                assert mode == commands["installed"], "CALIBRE_NATIVE_COMMAND"
                verify_installed(spec, directory, root, read_features)
        except Exception as error:
            print(str(error) if isinstance(error, AssertionError) else "CALIBRE_NATIVE_INPUT_INVALID", file=sys.stderr)
            sys.exit(1)
  '';
  # REPLACEABLE: rebuilt from the pinned Nix source and descriptor. The image
  # retains the eight vendor filenames/modes; no Nix store closure is installed.
  nativeBundle = pkgs.runCommand "calibre-ffmpeg-portable" {
    nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ];
  } ''
    mkdir -p "$out/lib"
    python3 - ${nativeSpec} ${nativeFfmpeg.lib}/lib "$out" <<'PYNATIVE'
    import hashlib, json, os, pathlib, shutil, subprocess, sys
    spec_file, source, output = map(pathlib.Path, sys.argv[1:])
    spec = json.loads(spec_file.read_text())
    assert {p.name.split(".so.")[0] for p in source.glob("*.so.*")} == set(spec["families"]), "CALIBRE_NATIVE_BUILT_FAMILIES"
    allowed = {name for value in spec["libraries"].values() for name in value["needed"]}
    files, used = {}, 0
    for name in spec["libraries"]:
        target = output / "lib" / name
        shutil.copyfile(source / name, target)
        target.chmod(0o755)
        for old, new in spec["dependencyAliases"].items():
            subprocess.run(["patchelf", "--replace-needed", old, new, str(target)], check=True)
        subprocess.run(["patchelf", "--set-rpath", "$ORIGIN", str(target)], check=True)
        def elf(flag):
            return subprocess.check_output(["patchelf", flag, str(target)], text=True).strip()
        needed, soname, rpath = elf("--print-needed").splitlines(), elf("--print-soname"), elf("--print-rpath")
        assert set(needed) <= allowed and soname == name and rpath == "$ORIGIN", "CALIBRE_NATIVE_PORTABLE_ABI"
        size = target.stat().st_size; used += size
        assert 0 < size <= spec["limits"]["fileBytes"] and used <= spec["limits"]["groupBytes"], "CALIBRE_NATIVE_BUILT_BOUND"
        with target.open("rb") as handle:
            sha = hashlib.file_digest(handle, "sha256").hexdigest()
        files[name] = dict(sha256=sha, bytes=size, soname=soname, needed=needed, rpath=rpath)
    raw = json.dumps(dict(schemaVersion=1, descriptor=spec, files=files), sort_keys=True, separators=(",", ":")).encode()
    assert len(raw) <= spec["limits"]["manifestBytes"], "CALIBRE_NATIVE_BUILT_MANIFEST_BOUND"
    (output / "manifest.json").write_bytes(raw)
    PYNATIVE
  '';
  nativeInputHash = builtins.hashString "sha256" (nativeSpec.text + nativeGuard.text + toString nativeBundle);
  nativeRoot = "${builtins.dirOf calibrePython}/lib";
  nativeStaging = "/tmp/hwc-calibre-native";
  nativeCommand = command: "RUN python3 -I -B ${nativeStaging}/guard.py ${command} ${nativeStaging}/spec.json ${nativeStaging} ${nativeRoot} ${nativeRoot}\n";
  # Temporary: vendor 9.17's frozen Python still accepts malformed chunks.
  # Retire after the unmodified vendor browser passes the framing/data contract.
  runtime = helpers.mkRuntimeImage {
    name = "calibre";
    version = "9.17.0-http-framing";
    recipe = ''
      FROM lscr.io/linuxserver/calibre@sha256:b198fc03a6abc6be7e251a9958e50e74634b00e447c7b25e92c191c8077ba378
      # Native inputs ${nativeInputHash}
      COPY native ${nativeStaging}
      COPY client.py /tmp/hwc-calibre-http/client.py
    '' + nativeCommand nativeDescriptor.commands.verify
      + nativeCommand nativeDescriptor.commands.apply
      + nativeCommand nativeDescriptor.commands.installed
      + httpBackport.recipe + "RUN rm -rf /tmp/hwc-calibre-http /tmp/hwc-frozen-config /tmp/hwc-frozen-cache ${nativeStaging}\n";
  };
  runtimeManifest = pkgs.writeText "calibre-http-framing.json" (builtins.toJSON httpBackport.manifest);
  # Pure asset API: Books can reuse this qualified distribution without enabling
  # the desktop service or copying its frozen-loader facts and implementation.
  runtimeAssets = pkgs.writeText "calibre-runtime-assets.json" (builtins.toJSON {
    schemaVersion = 1;
    image = runtime.image;
    python = calibrePython;
    rootPath = builtins.dirOf calibrePython;
    http = httpBackport.manifest;
    native = {
      schemaVersion = 1;
      descriptor = nativeDescriptor;
      inputHash = nativeInputHash;
      bundleInput = builtins.unsafeDiscardStringContext (toString nativeBundle);
    };
  });
  runtimeContext = pkgs.runCommand "calibre-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${httpSource} "$out/client.py"
    cp ${runtimeManifest} "$out/manifest.json"
    mkdir -p "$out/native"
    cp ${nativeSpec} "$out/native/spec.json"
    cp ${nativeGuard} "$out/native/guard.py"
    cp -r ${nativeBundle}/lib ${nativeBundle}/manifest.json "$out/native/"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.calibre = {
    enable = lib.mkEnableOption "Calibre ebook management container";
    # Critical library state: upgrade this immutable vendor image only after
    # current-data startup and compatible-code recovery checks pass.
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified Calibre 9.17.0 with frozen HTTP framing and same-ABI FFmpeg repairs"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU support for Calibre"; };
    ports = {
      desktop = lib.mkOption { type = lib.types.int; default = 8083; description = "Port for Calibre desktop interface (KasmVNC)"; };
      webserver = lib.mkOption { type = lib.types.int; default = 8181; description = "Port for Calibre content server"; };
    };
    library = lib.mkOption { type = lib.types.path; default = "${paths.media.books}/ebooks"; description = "Path to ebooks library"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    { system.build = {
      calibreRuntimeAssets = runtimeAssets;
      calibreRuntimeNativeSpec = nativeSpec;
      calibreRuntimeNativeGuard = nativeGuard;
      calibreRuntimeNativeBundle = nativeBundle;
    }; }
    (lib.mkIf cfg.enable {
      system.build.calibreRuntimeImageRecipe = runtime.dockerfile;
      system.build.calibreRuntimeImageContext = runtimeContext;
      systemd.services.podman-calibre.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
          echo "Prebuild Calibre from ${runtime.dockerfile} before activation" >&2
          exit 1
        }
      '');
      # Container definition is in sys.nix
      # Service dependencies are in parts/config.nix

      #==========================================================================
      # VALIDATION
      #==========================================================================
      assertions = helpers.mkVpnAssertions {
        name = "calibre";
        networkMode = cfg.network.mode;
        gluetunInstances = config.hwc.networking.gluetun.instances;
      } ++ [
        {
          assertion = config.hwc.paths.hot.root != null;
          message = "calibre container requires hwc.paths.hot.root to be defined (for downloads)";
        }
        {
          assertion = config.hwc.paths.media.root != null;
          message = "calibre container requires hwc.paths.media.root to be defined (for book libraries)";
        }
      ];
    })
  ];
}
