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
  # Temporary: the vendor native SSL predates CPython's compromised-key distrust.
  # Retire when the unmodified vendor passes the TLS/API/GUI/worker contract.
  # Artifact-only until the original-path, fresh-process consumer qualifies it.
  sslDescriptor = {
    schemaVersion = 1;
    pythonVersion = httpBackport.manifest.pythonVersion;
    opensslVersion = "3.5.9";
    advisory = "CVE-2026-115557";
    upstreamCommit = "e9bf2cf84eebf838a1edaa1c648c2b36345b99d3";
    patch = {
      url = "https://github.com/python/cpython/commit/${sslDescriptor.upstreamCommit}.patch";
      includes = [ "Modules/_ssl.c" "Modules/_ssl/distrusted_spki.h" ];
      hash = "sha256-golYkxggS4HEq/zTjv3TeI3AVKuqTqtKXCBrU+0Ky4E=";
    };
    sourceFiles = {
      "Modules/_ssl.c" = "208daac45832d0bc2297834e09e017098af38d406d44820c3f250b2026a22375";
      "Modules/_ssl/distrusted_spki.h" = "bff6ffbbdb400bcfee6d15f8309da2128157feb7d8be98d14041abe80fc9ff8e";
    };
    headers = {
      python = "9005ef414e92cd4b6ff6d9fdaafdee4d614b23df71c4ca1e1df4883c1f1e0c9c";
      openssl = "9647fc99758cf83e3bcf11ae310894fd4911ad62bff22d8213a614df89cfedda";
    };
    abiMacros = {
      Py_DEBUG = 0; Py_GIL_DISABLED = 0; WITH_PYMALLOC = 1;
      Py_ENABLE_SHARED = 1; SIZEOF_VOID_P = 8; SIZEOF_TIME_T = 8;
      Py_TRACE_REFS = 0; Py_STATS = 0; Py_REF_DEBUG = 0;
    };
    original = {
      path = "${builtins.dirOf calibrePython}/lib/calibre-extensions/_ssl.so";
      sha256 = "7b6f778ec806ec814430c70b72751c487953fefbac8bbf79d1db1d8aefce5c04";
      bytes = 236768;
      mode = 493;
      needed = [ "libc.so.6" "libcrypto.so.3" "libssl.so.3" ];
      apiSha256 = "6562f5b125c4e340777b2f7b750a37ed5ceb6818b9786674af803b14bb6c2e5e";
    };
    # Vendor reports build headers3.5.8 while actually loading3.5.9. Keep the
    # rebuilt module's truthful header metadata; every other member/constant
    # must match the original fingerprint after reversing this one change.
    apiConstantChanges."_OPENSSL_API_VERSION" = {
      original = [ 3 5 0 8 0 ];
      rebuilt = let v = map lib.toInt (lib.splitString "." sslDescriptor.opensslVersion);
        in [ (builtins.elemAt v 0) (builtins.elemAt v 1) 0 (builtins.elemAt v 2) 0 ];
    };
    apiSha256 = "4d9e4f1ec6c62f7aea031f35f0763597449f9bd1dc7b0d6ffe81a71b55b25e20";
    rpath = "$ORIGIN/..";
    limits = { fileBytes = 2097152; manifestBytes = 16384; sourceBytes = 524288; };
  };
  sslSpec = pkgs.writeText "calibre-native-ssl.json" (builtins.toJSON sslDescriptor);
  sslSourceGuard = pkgs.writeText "calibre-native-ssl-source-guard.py" ''
    import hashlib, json, pathlib, re, sys

    def check(spec, root, python_header, openssl_header):
        assert spec["schemaVersion"] == 1, "CALIBRE_SSL_SCHEMA"
        for name, expected in spec["sourceFiles"].items():
            path = root / name
            assert path.is_file() and not path.is_symlink(), "CALIBRE_SSL_SOURCE_TYPE"
            raw = path.read_bytes()
            assert 0 < len(raw) <= spec["limits"]["sourceBytes"], "CALIBRE_SSL_SOURCE_BOUND"
            assert hashlib.sha256(raw).hexdigest() == expected, "CALIBRE_SSL_SOURCE_DRIFT"
        for name, path in [("python", python_header), ("openssl", openssl_header)]:
            assert path.is_file() and not path.is_symlink(), "CALIBRE_SSL_HEADER_TYPE"
            raw = path.read_bytes()
            assert 0 < len(raw) <= spec["limits"]["sourceBytes"], "CALIBRE_SSL_HEADER_BOUND"
            assert hashlib.sha256(raw).hexdigest() == spec["headers"][name], "CALIBRE_SSL_HEADER_DRIFT"
        text = python_header.read_text()
        for name, expected in spec["abiMacros"].items():
            values = re.findall(r"^#define " + re.escape(name) + r"\s+(\d+)\s*$", text, re.M)
            assert len(values) <= 1 and (int(values[0]) if values else 0) == expected, "CALIBRE_SSL_ABI_DRIFT"
        text = openssl_header.read_text()
        actual = [int(re.search(r"^#\s*define OPENSSL_VERSION_" + name + r"\s+(\d+)\s*$", text, re.M)[1])
                  for name in ["MAJOR", "MINOR", "PATCH"]]
        assert actual == list(map(int, spec["opensslVersion"].split("."))), "CALIBRE_SSL_OPENSSL_DRIFT"

    if __name__ == "__main__":
        if not __debug__:
            raise AssertionError("CALIBRE_SSL_OPTIMIZED_GUARD")
        spec, root, python_header, openssl_header = map(pathlib.Path, sys.argv[1:])
        assert spec.stat().st_size <= 16384, "CALIBRE_SSL_SPEC_BOUND"
        check(json.loads(spec.read_text()), root, python_header, openssl_header)
        print("CALIBRE_SSL_SOURCE_FIXED")
  '';
  # REPLACEABLE: one native module rebuilt from the pinned source and SDK.
  # Do not run Python's full configure/build or link a second libpython.
  sslPackage = assert lib.assertMsg
    (pkgs.python314.version == lib.concatMapStringsSep "." toString sslDescriptor.pythonVersion
      && pkgs.openssl_3_5.version == sslDescriptor.opensslVersion)
    "Calibre SSL requires the measured Python and OpenSSL SDK versions";
    pkgs.stdenv.mkDerivation {
      pname = "calibre-native-ssl";
      version = pkgs.python314.version;
      src = pkgs.python314.src;
      patches = [ (pkgs.fetchpatch sslDescriptor.patch) ];
      patchFlags = [ "-p1" "--fuzz=0" ];
      nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ];
      buildInputs = [ pkgs.openssl_3_5 ];
      dontConfigure = true;
      postPatch = ''
        python3 -I -B ${sslSourceGuard} ${sslSpec} . \
          ${pkgs.python314}/include/python3.14/pyconfig.h \
          ${lib.getDev pkgs.openssl_3_5}/include/openssl/opensslv.h
      '';
      buildPhase = ''
        runHook preBuild
        $CC -shared -fPIC -O2 -DNDEBUG -fno-strict-aliasing \
          -I${pkgs.python314}/include/python3.14 \
          -I${pkgs.python314}/include/python3.14/internal \
          -I${lib.getDev pkgs.openssl_3_5}/include \
          -I${lib.getDev pkgs.bluez}/include \
          Modules/_ssl.c -L${lib.getLib pkgs.openssl_3_5}/lib -lssl -lcrypto -o _ssl.so
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/lib"
        install -m755 _ssl.so "$out/lib/_ssl.so"
        runHook postInstall
      '';
      # Run after Nix's strip/RPATH fixups: the output loads vendor libraries
      # beside the original target, not the Nix build SDK's runtime closure.
      postFixup = ''
        patchelf --set-rpath ${lib.escapeShellArg sslDescriptor.rpath} "$out/lib/_ssl.so"
        python3 -I -B - ${sslSpec} "$out" <<'PYSSL'
        import hashlib, json, pathlib, subprocess, sys
        spec_file, output = map(pathlib.Path, sys.argv[1:])
        spec = json.loads(spec_file.read_text())
        path = output / "lib/_ssl.so"
        def elf(flag):
            return subprocess.check_output(["patchelf", flag, str(path)], text=True).strip()
        needed, rpath, soname = sorted(elf("--print-needed").splitlines()), elf("--print-rpath"), elf("--print-soname")
        assert needed == spec["original"]["needed"] and rpath == spec["rpath"] and not soname, "CALIBRE_SSL_PORTABLE_ABI"
        raw = path.read_bytes()
        assert 0 < len(raw) <= spec["limits"]["fileBytes"], "CALIBRE_SSL_BUILT_BOUND"
        result = dict(schemaVersion=1, descriptor=spec, file=dict(sha256=hashlib.sha256(raw).hexdigest(),
            bytes=len(raw), needed=needed, rpath=rpath, soname=soname))
        raw = json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
        assert len(raw) <= spec["limits"]["manifestBytes"], "CALIBRE_SSL_MANIFEST_BOUND"
        (output / "manifest.json").write_bytes(raw)
        PYSSL
      '';
    };
  # Upstream7.1 maintenance keeps RELEASE7.1.5; bind its exact revision
  # and complete post-patch source separately from the library version.
  nativeSourceFacts = builtins.fromJSON ''
{
  "schemaVersion": 1,
  "sourceRevision": "f9db090b14c255a8f1c5f8f41a4c92b723228763",
  "sourceSha256": {
    "libavcodec/adxdec.c": "801f06624465f5e5f08e4582bc70dd925d767f50a8d0a530edb1510d78208006",
    "libavcodec/cfhd.c": "0588d773b1c4e8fa2427bb6737e8317a9c76427dc21587596a918e5cb99b484d",
    "libavcodec/dvbsub_parser.c": "71e716bc56433b8a46c1d5c8a1a5fb454731b3fea7b7e95b7d4a5cc64d37d073",
    "libavcodec/lcldec.c": "8974c46459aa97eeb68f14cd6d371e0d5032790aa5acce71900e6a5e267c1544",
    "libavcodec/mace.c": "b982ff4276da9a87f19c334e4f92f5317f4ef4bd758682deb335ed30a0be050f",
    "libavcodec/rscc.c": "774382c170ff4603590120b1dbd9190ac48f446a521ef34e5870c6bbe3d104b0",
    "libavcodec/screenpresso.c": "882d6e383c4ccf44af608e0aca385e038c36762b5142268e942388ee3248833e",
    "libavcodec/tdsc.c": "59455f38dca7f007f2abef4493463880b3311aeb0a3ce78568e11af99b402a45",
    "libavcodec/tiff.c": "d71d08c601fe824970515c640cc72c39e497297828c8f8d183e8e4801e4438b3",
    "libavfilter/avfilter.c": "dd869e2e7c85037d07458da1dcb3ff95db3b97d9c0442a72df3608202332ed2d",
    "libavfilter/vf_floodfill.c": "1a1dfb0a028421a843fb672ba40e9e66e5b25c0ae7c1bd8149b2f90ad7029fca",
    "libavfilter/vf_hqdn3d.c": "02664152f7a9679c989185dfa66ac27484a3bb14850a8026a5313f256c989831",
    "libavfilter/vf_hqdn3d.h": "15de9174517591c41d2df3874376cd7271c43748745f4437e9cb7b9209dbd4b9",
    "libavfilter/vf_swaprect.c": "9d5875d821d4bf670094ec09d91f8b2ec67dbcb7556e17df22a4e75ad09def45",
    "libavformat/hls.c": "a297662d8e83c1067b905fb198af7c47bacbb20d184195da52335d04e4fc13d7",
    "libavformat/isom.h": "cb23c58f760cc13c66b2fb3bced1478886133eb46dc8bc4fd73ebc1141a5b8aa",
    "libavformat/mov.c": "bed4eb73bba5000e5b8a86bb3f9d32568738b3e5d84581ec6d4ccc94a22631a4",
    "libavformat/mpeg.c": "75a8c8b1c5642b313cebae32621a85e443eb8920e08836da43c24221d5c57659",
    "libavformat/rtpdec_asf.c": "b4748d01fbe4971e7273519e6b5fbccea9f21aa9f2a9f48a5920ce1773e1a707",
    "libavformat/rtsp.c": "204cff07d490b0422c8ed4676e8e1997c5b36d052e4a410a265b3916ee085bc5",
    "libavformat/spdifenc.c": "7a6d6eba8a3d26570114fd17bd3503f339520c5a3db6164c98f6ead38f514294",
    "libavformat/ty.c": "2b89305396b5be7bff698068356c7a0c37799f177c4c99e79645bc30b9f66338",
    "libavutil/encryption_info.c": "012a2b4d31c2f5311ea97e16b19c77ecc2c25d44f712bf5c69f8b82334ca7075",
    "libavutil/encryption_info.h": "782fcd91eee6cce50eb6336d6311c4c113a38f1d8f21e6cc1eb616cb1cac653b",
    "libavutil/hdr_dynamic_metadata.c": "70876a30e7ac083375382ea48df91ff1c0e5590f13a8957ffbb058139cba417b",
    "libavutil/tests/encryption_info.c": "336c641861b4b735cbbf1dbb3bcdea8a90db6e43d19107d43eb0170d2f80de67",
    "libavformat/avformat.h": "352ccf1aa9f92ebdf05a3d7d7d9493b9c9371e6b8320984341e1b20785e6a377",
    "libavformat/mux_utils.c": "902aeff13cb7c922d697e431bc0a28ec677b3514b2354c960bfad11e478482bf"
  }
}
  '';
  # The Nix Chromium extension is retained. Its historical patch matched7.1
  # only with fuzz2; adapt context and check the exact same function bytes.
  # Retire when the Nix patch applies to this source with --fuzz=0.
  nativeNixPatchContext = builtins.fromJSON ''
[
  [
    "@@ -1128,6 +1128,10 @@\n  */\n int64_t    av_stream_get_end_pts(const AVStream *st);\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t    av_stream_get_first_dts(const AVStream *st);\n+// Chromium: We use the internal field first_dts ^^^\n+\n #define AV_PROGRAM_RUNNING 1\n \n /**\n",
    "@@ -1202,6 +1202,10 @@\n \n struct AVCodecParserContext *av_stream_get_parser(const AVStream *s);\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t    av_stream_get_first_dts(const AVStream *st);\n+// Chromium: We use the internal field first_dts ^^^\n+\n #define AV_PROGRAM_RUNNING 1\n \n /**\n"
  ],
  [
    "@@ -37,6 +37,13 @@\n         return AV_NOPTS_VALUE;\n }\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t av_stream_get_first_dts(const AVStream *st)\n+{\n+  return cffstream(st)->first_dts;\n+}\n+// Chromium: We use the internal field first_dts ^^^\n+\n int avformat_query_codec(const AVOutputFormat *ofmt, enum AVCodecID codec_id,\n                          int std_compliance)\n {\n",
    "@@ -29,6 +29,13 @@\n #include \"avio.h\"\n #include \"internal.h\"\n #include \"mux.h\"\n+\n+// Chromium: We use the internal field first_dts vvv\n+int64_t av_stream_get_first_dts(const AVStream *st)\n+{\n+  return cffstream(st)->first_dts;\n+}\n+// Chromium: We use the internal field first_dts ^^^\n \n int avformat_query_codec(const AVOutputFormat *ofmt, enum AVCodecID codec_id,\n                          int std_compliance)\n"
  ]
]
  '';
  nativeSecurity = helpers.selectFfmpegSecurityBackports {
    advisories = [ "CVE-2026-107676" "CVE-2026-107678" "CVE-2026-107695" "CVE-2026-107696" "CVE-2026-107697" "CVE-2026-64830" "CVE-2026-64833" "CVE-2026-64834" "CVE-2026-64835" "CVE-2026-65703" "CVE-2026-65704" "CVE-2026-65705" "CVE-2026-65706" "CVE-2026-66036" "CVE-2026-66038" "CVE-2026-66039" "CVE-2026-70628" "CVE-2026-70629" "CVE-2026-70630" "CVE-2026-70631" "CVE-2026-70632" ];
    # Adapt branch context only; preserve all upstream security additions.
    contextEdits = builtins.fromJSON ''
{
  "eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97": [
    [
      "@@ -2243,6 +2244,11 @@ redirect:\n     if (reply->status_code >=300 && reply->status_code < 400 && s->iformat) {\n         int ret;\n \n+        if (redirects++ >= 8 /* MAX_RTSP_REDIRECTS */) {\n+            av_log(s, AV_LOG_ERROR, \"Too many RTSP redirects\\n\");\n+            err = AVERROR(EIO);\n+            goto fail2;\n+        }\n         if (!rtsp_url_same_origin(s->url, reply->location)) {\n             memset(rt->auth, 0, sizeof(rt->auth));\n             memset(&rt->auth_state, 0, sizeof(rt->auth_state));\n",
      "@@ -2243,6 +2244,11 @@ redirect:\n     if (reply->status_code >=300 && reply->status_code < 400 && s->iformat) {\n+        if (redirects++ >= 8 /* MAX_RTSP_REDIRECTS */) {\n+            av_log(s, AV_LOG_ERROR, \"Too many RTSP redirects\\n\");\n+            err = AVERROR(EIO);\n+            goto fail2;\n+        }\n         char *new_url = av_strdup(reply->location);\n         if (!new_url) {\n             err = AVERROR(ENOMEM);\n             goto fail2;\n         }\n"
    ]
  ],
  "62294b6a8ad2370e1435bb9985ebe6b53be14c2b": [
    [
      "@@ -1078,7 +1078,8 @@ int ff_filter_frame(AVFilterLink *link, AVFrame *frame)\n             strcmp(link->dst->filter->name, \"idet\") &&\n             strcmp(link->dst->filter->name, \"null\") &&\n             strcmp(link->dst->filter->name, \"scale\") &&\n-            strcmp(link->dst->filter->name, \"libplacebo\")) {\n+            strcmp(link->dst->filter->name, \"libplacebo\") &&\n+            strcmp(link->dst->filter->name, \"hqdn3d\")) {\n             av_assert1(frame->format        == link->format);\n             av_assert1(frame->width         == link->w);\n             av_assert1(frame->height        == link->h);\n",
      "@@ -1078,6 +1078,7 @@ int ff_filter_frame(AVFilterLink *link, AVFrame *frame)\n             strcmp(link->dst->filter->name, \"idet\") &&\n             strcmp(link->dst->filter->name, \"null\") &&\n-            strcmp(link->dst->filter->name, \"scale\")) {\n+            strcmp(link->dst->filter->name, \"scale\") &&\n+            strcmp(link->dst->filter->name, \"hqdn3d\")) {\n             av_assert1(frame->format        == link->format);\n             av_assert1(frame->width         == link->w);\n             av_assert1(frame->height        == link->h);\n"
    ]
  ]
}
  '';
  };
  nativeSourceSpec = pkgs.writeText "calibre-native-source.json" (builtins.toJSON nativeSourceFacts);
  nativeSourceGuard = pkgs.writeText "calibre-native-source-guard.py" ''
    import hashlib, json, pathlib, re, sys
    if sys.flags.optimize:
        raise RuntimeError('CALIBRE_NATIVE_SOURCE_OPTIMIZED')
    spec_file, root = map(pathlib.Path, sys.argv[1:])
    assert spec_file.stat().st_size <= 65536, 'CALIBRE_NATIVE_SOURCE_SPEC_BOUND'
    spec = json.loads(spec_file.read_text())
    assert spec['schemaVersion'] == 1, 'CALIBRE_NATIVE_SOURCE_SCHEMA'
    assert re.fullmatch('[0-9a-f]{40}', spec['sourceRevision']), 'CALIBRE_NATIVE_SOURCE_REVISION'
    files = spec['sourceSha256']
    assert 1 <= len(files) <= 64, 'CALIBRE_NATIVE_SOURCE_COUNT'
    used = 0
    for name, expected in files.items():
        relative = pathlib.Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts, 'CALIBRE_NATIVE_SOURCE_PATH'
        path = root / relative
        assert path.is_file() and not path.is_symlink(), 'CALIBRE_NATIVE_SOURCE_FILE'
        assert path.stat().st_size <= 2097152, 'CALIBRE_NATIVE_SOURCE_FILE_BOUND'
        raw = path.read_bytes()
        used += len(raw)
        assert used <= 16777216, 'CALIBRE_NATIVE_SOURCE_GROUP_BOUND'
        assert hashlib.sha256(raw).hexdigest() == expected, 'CALIBRE_NATIVE_SOURCE_DRIFT'
    print('CALIBRE_NATIVE_SOURCE_FIXED', len(files))
  '';
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
    src = pkgs.fetchFromGitHub {
      owner = "FFmpeg"; repo = "FFmpeg"; name = "ffmpeg";
      rev = nativeSourceFacts.sourceRevision;
      hash = "sha256-trLrw4misl9NvXgXrr44Wc1ImPvcPX/KzDyFRsrj8mU=";
    };
    patches = map (patch:
      if lib.hasSuffix "-add-av_stream_get_first_dts-for-chromium.patch" (toString patch)
      then helpers.adaptFfmpegPatchContext {
        upstream = patch; edits = nativeNixPatchContext; name = "chromium-first-dts";
      } else patch
    ) old.patches ++ nativeSecurity.patches;
    patchFlags = [ "-p1" "--fuzz=0" ];
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python3 -I -B ${nativeSourceGuard} ${nativeSourceSpec} .
    '';
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
    securityBackports = nativeSourceFacts // { inherit (nativeSecurity) advisories commits; };
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
      calibreRuntimeNativeSourceSpec = nativeSourceSpec;
      calibreRuntimeNativeSourceGuard = nativeSourceGuard;
      calibreRuntimeNativePackage = nativeFfmpeg;
      calibreRuntimeNativeGuard = nativeGuard;
      calibreRuntimeNativeBundle = nativeBundle;
      calibreRuntimeSslSpec = sslSpec;
      calibreRuntimeSslSourceGuard = sslSourceGuard;
      calibreRuntimeSslPackage = sslPackage;
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
