{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.books;
  # Same application/schema, updated immutable native/Python base. Pins are
  # permanent by design; replace only after compatible current-data recovery.
  # Retire the HTTP and request-options adapters when the unmodified vendor
  # passes malformed/normal, actual socket/proxy and current-data contracts.
  assets = let value = builtins.fromJSON config.system.build.calibreRuntimeAssets.text;
    in assert value.schemaVersion == 1; value;
  specBase = {
    schemaVersion = 1;
    commands = { verify = "verify"; apply = "apply"; };
    pythonVersion = "3.14.4";
    sourceImage = "lscr.io/linuxserver/lazylibrarian@sha256:05515b7c4485fc4816679a60a97c794e27c0c4ceab788c58ae003461be7a158a";
    baseImage = "lscr.io/linuxserver/lazylibrarian@sha256:589139e7eb33faa87b090efd098f63f3c75a0ea2fb4986209f418e663ff5d324";
    app = {
      databaseVersion = 89;
      # The inherited init copies this marker into the persistent config cache.
      # Keep it with the retained application, rather than the new native base.
      versionMarkerSha256 = "19bffcb65bfd2240adcdfd2aeacb0348ca0a93bdeab399e7d822ffd2c5f3f90c";
      fileCount = 384;
      sourceDistributionSha256 = "fa4a02dedc8a707323fb9ab5fbcb1a67bcc29c01d8ef0e4873075b0739e84bdd";
      patchedDistributionSha256 = "3f5545e1fc8a32d36fdb5fc7111f46f39126472ffc54f9e1c2ce3a43c11cf26c";
      requestOptions = {
        path = "lazylibrarian/cache.py";
        sourceSha256 = "a781620714277ce311009c74403b223d3959932b1b6b2bb682e35cee2f12761d";
        patchedSha256 = "b9f5ad16b59fe93a1b891680512a2bc7d8977dfb2d4701cef4d5f092046af5c5";
        old = "params=payload, headers=headers";
        new = "headers=headers, **payload";
        count = 3;
      };
    };
    pythonPackages = { requests = "2.34.2"; urllib3 = "2.8.0"; };
    nativePackages = [
      { name = "libasound2-data"; version = "1.2.15.3-1ubuntu1.1"; architecture = "all";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/a/alsa-lib/libasound2-data_1.2.15.3-1ubuntu1.1_all.deb"; sha256 = "aad0eb27b9fab12c9fa9ed0b223c7ce871003fd3a564ad8eca4ecdea978ac347"; }
      { name = "libasound2t64"; version = "1.2.15.3-1ubuntu1.1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/a/alsa-lib/libasound2t64_1.2.15.3-1ubuntu1.1_amd64.deb"; sha256 = "96e20cf5c9095ef54ba46fccffea5c01cf2de17a1012c5683a67e43504a6d726"; }
      { name = "libdrm-amdgpu1"; version = "2.4.131-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm-amdgpu1_2.4.131-1_amd64.deb"; sha256 = "f992d3b87be69d160d433626e2144f6446946143cb83bdc71adef71766783de0"; }
      { name = "libdrm-common"; version = "2.4.131-1"; architecture = "all";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm-common_2.4.131-1_all.deb"; sha256 = "a32b8d623c04310d049cde28cdbbd339575cdc26c8dc741d7de708a954eff528"; }
      { name = "libdrm-intel1"; version = "2.4.131-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm-intel1_2.4.131-1_amd64.deb"; sha256 = "77411c3b93c8756862a18ccaa4413a65777f40819abdd1468954ba859c8aa740"; }
      { name = "libdrm2"; version = "2.4.131-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm2_2.4.131-1_amd64.deb"; sha256 = "b87e6f715d0795a88b53fbe268004a1acbd0d728da0cc0ab9108aff5ab4e1929"; }
      { name = "libegl-mesa0"; version = "26.0.8-1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libegl-mesa0_26.0.8-1ubuntu0.3_amd64.deb"; sha256 = "938813d9d6bb7ccf8315af1f8bb2770ad4b9d240ad177f0da420db3e94600d6b"; }
      { name = "libegl1"; version = "1.7.0-3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libg/libglvnd/libegl1_1.7.0-3_amd64.deb"; sha256 = "cf2a6549bbc4339671901bde97c0ca41c380c5783179ef68977bf86151f03766"; }
      { name = "libelf1t64"; version = "0.194-4"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/e/elfutils/libelf1t64_0.194-4_amd64.deb"; sha256 = "c2feae172b14d2a8317348023c5e0b6572314c097a9f7b8225c62b0988cc8d92"; }
      { name = "libgbm1"; version = "26.0.8-1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libgbm1_26.0.8-1ubuntu0.3_amd64.deb"; sha256 = "5d2d1eaf0f72c5a2c4aef692e5660c6fa61e46542c4d9cb5593ba8bd020b2eea"; }
      { name = "libgl1-mesa-dri"; version = "26.0.8-1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libgl1-mesa-dri_26.0.8-1ubuntu0.3_amd64.deb"; sha256 = "585dfac64d7ca95a9813faad9f14c361d788069b7578859fb426c657dd528f08"; }
      { name = "libgl1"; version = "1.7.0-3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libg/libglvnd/libgl1_1.7.0-3_amd64.deb"; sha256 = "83ec3a454b28e947a6886e9ae8167e129e25d7a2fd741aaffcdca76eddff5955"; }
      { name = "libglvnd0"; version = "1.7.0-3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libg/libglvnd/libglvnd0_1.7.0-3_amd64.deb"; sha256 = "db2cd8cff67e3e210f5223dfe41f000efd4d3d887ab05bda2e88c4a622f12b36"; }
      { name = "libglx-mesa0"; version = "26.0.8-1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libglx-mesa0_26.0.8-1ubuntu0.3_amd64.deb"; sha256 = "17ff6239daaf75337d3697c1e5f1ef3e190c4c2dd73a9f0edfc36868ef41905c"; }
      { name = "libglx0"; version = "1.7.0-3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libg/libglvnd/libglx0_1.7.0-3_amd64.deb"; sha256 = "e0b75c32f773201ebca2184d94dfc34f6e09470c7cf6e425d48b270e516fd909"; }
      { name = "libllvm21"; version = "1:21.1.8-6ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/l/llvm-toolchain-21/libllvm21_21.1.8-6ubuntu1_amd64.deb"; sha256 = "9e758998dcb4aa27abbe64f2dee7bc490d9eb0721afa334a82a2b1bf6c7648f9"; }
      { name = "libnspr4"; version = "2:4.38.2-1ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/n/nspr/libnspr4_4.38.2-1ubuntu1_amd64.deb"; sha256 = "2f28284b35765aaccad1785ab017425e1ca378c395256331f9c662d04335d43f"; }
      { name = "libnss3"; version = "2:3.120-1ubuntu2.2"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/n/nss/libnss3_3.120-1ubuntu2.2_amd64.deb"; sha256 = "7c5843f5e49c10c267893ae7f13af6032ed1b96e7c1ae586a5f44435f804dd85"; }
      { name = "libopengl0"; version = "1.7.0-3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libg/libglvnd/libopengl0_1.7.0-3_amd64.deb"; sha256 = "ccdcf477a19c1f51c20aa7569e953dbb5bc9456b57e2d3e325f8fda2650106ca"; }
      { name = "libpciaccess0"; version = "0.18.1-1ubuntu4.1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libp/libpciaccess/libpciaccess0_0.18.1-1ubuntu4.1_amd64.deb"; sha256 = "8733699ae9d7102a84cd10a1f0f0769b684c6ca8842035db389bb6b8310f72dd"; }
      { name = "libsensors-config"; version = "1:3.6.2-2build1"; architecture = "all";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/libsensors-config_3.6.2-2build1_all.deb"; sha256 = "57193f731de79bbad343a1369e6e95b13096c08ba166c7e193bfc24d78f960fb"; }
      { name = "libsensors5"; version = "1:3.6.2-2build1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/libsensors5_3.6.2-2build1_amd64.deb"; sha256 = "9249cd2be68acd7b589030df72a457b89fadea6c426002b00648ad2d153d9748"; }
      { name = "libvulkan1"; version = "1.4.341.0-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/v/vulkan-loader/libvulkan1_1.4.341.0-1_amd64.deb"; sha256 = "b4aca7a519d6318347f15a0e485c636603005e2553dae1a986272ac8c96176b0"; }
      { name = "libwayland-client0"; version = "1.24.0-2"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/w/wayland/libwayland-client0_1.24.0-2_amd64.deb"; sha256 = "094db0e190b53872e4d5310cd5fa09ca28ee3936386cd09e5f7d13e645aa12ab"; }
      { name = "libx11-xcb1"; version = "2:1.8.13-1ubuntu0.1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libx11/libx11-xcb1_1.8.13-1ubuntu0.1_amd64.deb"; sha256 = "23d0a8c5d8be6dc1ca39d5ea66c139ee56ab20116f11bae586e0dc1685682578"; }
      { name = "libxcb-dri3-0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-dri3-0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "2e0e3916c647a74e081621f385aa296dab3052b2582b0781d9fbea2f15696ef4"; }
      { name = "libxcb-glx0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-glx0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "857c34618ae56b2577d8d439cf86f80375582626193efaa3229c6767106a1a20"; }
      { name = "libxcb-present0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-present0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "64f23e7166461758d158220305e93a98fe75c570b68f96303a1c2395a58d5d7d"; }
      { name = "libxcb-randr0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-randr0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "78977a067ec1d59bb4ded1b35835d0ba70e6538aac1ea7edefe413795aaa0d4f"; }
      { name = "libxcb-shm0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-shm0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "e70d52936aabd7a90e9cd8af0f54ca050cde244f8382ffc5524ba65117c199c4"; }
      { name = "libxcb-sync1"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-sync1_1.17.0-2ubuntu1_amd64.deb"; sha256 = "8883f5e6badab24cb7487390bf1a888bb714e406f6c799345c33e4b69a8f3112"; }
      { name = "libxcb-xfixes0"; version = "1.17.0-2ubuntu1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcb/libxcb-xfixes0_1.17.0-2ubuntu1_amd64.deb"; sha256 = "00c1381b61e2e5b8a78e89b15818a214a8f44f1fae6a9ddd95e7c61de8ea33d2"; }
      { name = "libxcomposite1"; version = "1:0.4.6-1build1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxcomposite/libxcomposite1_0.4.6-1build1_amd64.deb"; sha256 = "b8557d5aba1e575acfb169f47e798c449c8a5ca05846861f1480724d4cfc5ce3"; }
      { name = "libxdamage1"; version = "1:1.1.7-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxdamage/libxdamage1_1.1.7-1_amd64.deb"; sha256 = "dd751597c6216105774a93769972d1cb6dad5fd1ba91f090197d7acc85c406cb"; }
      { name = "libxkbcommon0"; version = "1.13.1-1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxkbcommon/libxkbcommon0_1.13.1-1_amd64.deb"; sha256 = "7988d2375d10277ab4a54641aa6181accfaf3f5d25e48b050bf42a9583d4f926"; }
      { name = "libxkbfile1"; version = "1:1.1.0-1build5"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxkbfile/libxkbfile1_1.1.0-1build5_amd64.deb"; sha256 = "40bf42bc549b5d1f848e2ce8c1bafc9777e0fd4b943bbff922dd340f7ab3f5d7"; }
      { name = "libxml2-16"; version = "2.15.2+dfsg-0.1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2-16_2.15.2%2bdfsg-0.1ubuntu0.3_amd64.deb"; sha256 = "e82ce35fd61483c1febf83232e76e54a296a6a78391983a24a904ff640b75c09"; }
      { name = "libxrandr2"; version = "2:1.5.4-1build1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxrandr/libxrandr2_1.5.4-1build1_amd64.deb"; sha256 = "d0052315ac1417234777c0872568a86fce4d3a3316c041e5a2200da70f43a855"; }
      { name = "libxrender1"; version = "1:0.9.12-1build1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxrender/libxrender1_0.9.12-1build1_amd64.deb"; sha256 = "60b2f01e8124318e2a11049b82c764fd4c05c21adba11312e93ab116d6594f1e"; }
      { name = "libxshmfence1"; version = "1.3.3-1build1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxshmfence/libxshmfence1_1.3.3-1build1_amd64.deb"; sha256 = "85d6b6883a35e1a3b78af3dda6bb6b843c06cbead030a00d9de7d31a8077d562"; }
      { name = "libxtst6"; version = "2:1.2.5-1ubuntu0.1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxtst/libxtst6_1.2.5-1ubuntu0.1_amd64.deb"; sha256 = "09fc9803cfd2d00987e4e55123f845b1b77c3bf98eaf7ad2549caa938ac73fdd"; }
      { name = "libxxf86vm1"; version = "1:1.1.4-2"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxxf86vm/libxxf86vm1_1.1.4-2_amd64.deb"; sha256 = "ff01ae50526c23c6c747e1efd98ee3785a1d28458e865277fc367c565bb94703"; }
      { name = "mesa-libgallium"; version = "26.0.8-1ubuntu0.3"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/mesa-libgallium_26.0.8-1ubuntu0.3_amd64.deb"; sha256 = "7f123a545774034793ba3516c5fad0be88de68ad91319a4b220d98b32a289451"; }
      { name = "xkb-data"; version = "2.46-2"; architecture = "all";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/x/xkeyboard-config/xkb-data_2.46-2_all.deb"; sha256 = "a24f82b33020836444593a7ffbed959458852e28cfe16de2ff95bcbdcfbdb2d3"; }
      { name = "xz-utils"; version = "5.8.3-1ubuntu0.1"; architecture = "amd64";
        url = "http://archive.ubuntu.com/ubuntu/pool/main/x/xz-utils/xz-utils_5.8.3-1ubuntu0.1_amd64.deb"; sha256 = "5a1532b0f903040ba44a7459d20abb9163e300e081cf233eecc9cdfec33a6cd8"; }
    ];
  };
  nativePackages = map (entry: entry // { filename = "${entry.name}.deb"; }) specBase.nativePackages;
  pythonMinor = lib.concatStringsSep "." (lib.take 2 (lib.splitVersion specBase.pythonVersion));
  framing = helpers.mkPythonHttpFramingBackport {
    python = "/lsiopy/bin/python3";
    stdlibUpstreamCommits = pkgs.pythonHttpFramingBackport.upstreamCommits;
    modules = {
      httpClient = {
        path = "/usr/lib/python${pythonMinor}/http/client.py";
        inherit (pkgs.pythonHttpFramingBackport.distroSources."ubuntu-3.14.4-1ubuntu0.2") sourceSha256 patchedSha256;
        replacements = pkgs.pythonHttpFramingBackport.replacements;
      };
      urllib3 = {
        path = "/lsiopy/lib/python${pythonMinor}/site-packages/urllib3/response.py";
        inherit (pkgs.pythonUrllib3FramingBackport.sources.${specBase.pythonPackages.urllib3}) sourceSha256 patchedSha256;
        replacements = pkgs.pythonUrllib3FramingBackport.replacements;
      };
    };
  };
  environment = {
    DOCKER_MODS = "";
    PYTHONDONTWRITEBYTECODE = "1";
    ${assets.http.selectionVariable} = assets.http.rootPath;
  };
  spec = specBase // { inherit nativePackages environment; calibre = assets; framing = framing.manifest; };
  guard = ''
    import ast, hashlib, importlib.metadata, itertools, json, os, stat, subprocess, sys
    from pathlib import Path

    def digest(raw):
        return hashlib.sha256(raw).hexdigest()

    def app_files(root):
        assert root.is_dir() and not root.is_symlink(), 'BOOKS_APP_ROOT'
        files, used, directories = {}, 0, 0
        for parent, dirs, names in os.walk(root, followlinks=False):
            dirs[:] = sorted(name for name in dirs if name not in {'.git', '__pycache__'})
            directories += len(dirs)
            assert directories <= 512 and all(not (Path(parent) / name).is_symlink() for name in dirs), 'BOOKS_APP_DIRECTORIES'
            for name in sorted(names):
                path = Path(parent) / name
                if path.suffix in {'.pyc', '.pyo'}:
                    continue
                relative = str(path.relative_to(root))
                assert len(files) < 1024, 'BOOKS_APP_FILE_BOUND'
                if path.is_symlink():
                    files[relative] = {'link': os.readlink(path)}
                    continue
                identity = path.stat()
                assert stat.S_ISREG(identity.st_mode), 'BOOKS_APP_FILE_TYPE'
                used += identity.st_size
                assert used <= 33554432, 'BOOKS_APP_BYTE_BOUND'
                with path.open('rb') as source:
                    sha = hashlib.file_digest(source, 'sha256').hexdigest()
                files[relative] = {'sha256': sha, 'bytes': identity.st_size, 'mode': identity.st_mode & 0o777}
        return files

    def distribution(files):
        return digest(json.dumps(files, sort_keys=True, separators=(',', ':')).encode())

    def read_hash(path, maximum):
        assert path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum, 'BOOKS_INPUT_TYPE_BOUND'
        with path.open('rb') as source:
            return hashlib.file_digest(source, 'sha256').hexdigest()

    def verify(spec, app, inputs, calibre, hook, version, versions, deb_metadata):
        assert spec['schemaVersion'] == 1 and version == spec['pythonVersion'], 'BOOKS_RUNTIME_VERSION'
        assert versions == spec['pythonPackages'], 'BOOKS_PYTHON_PACKAGES'
        assert spec['framing']['schemaVersion'] == 1 and set(spec['framing']['modules']) == {'httpClient', 'urllib3'}, 'BOOKS_HTTP_PAIR'
        for entry in spec['framing']['modules'].values():
            assert read_hash(Path(entry['path']), 262144) == entry['sourceSha256'], 'BOOKS_HTTP_SOURCE'
        files = app_files(app)
        assert len(files) == spec['app']['fileCount'] and distribution(files) == spec['app']['sourceDistributionSha256'], 'BOOKS_APP_SOURCE'
        nodes = ast.parse((app / 'lazylibrarian/dbupgrade.py').read_text()).body
        actual = [ast.literal_eval(node.value) for node in nodes if isinstance(node, ast.Assign)
                  and any(isinstance(name, ast.Name) and name.id == 'db_current_version' for name in node.targets)]
        assert actual == [spec['app']['databaseVersion']], 'BOOKS_APP_DATABASE_VERSION'
        packages = spec['nativePackages']
        assert packages and len({entry['filename'] for entry in packages}) == len(packages), 'BOOKS_NATIVE_SET'
        assert {path.name for path in inputs.iterdir()} == {entry['filename'] for entry in packages}, 'BOOKS_NATIVE_INPUT_SET'
        for entry in packages:
            assert entry['filename'] == entry['name'] + '.deb', 'BOOKS_NATIVE_FILENAME'
            path = inputs / entry['filename']
            assert read_hash(path, 67108864) == entry['sha256'], 'BOOKS_NATIVE_SOURCE'
            assert deb_metadata(path) == {key: entry[key] for key in ['name', 'version', 'architecture']}, 'BOOKS_NATIVE_METADATA'
        provider = spec['calibre']
        assert provider['schemaVersion'] == 1, 'BOOKS_CALIBRE_API_VERSION'
        http = provider['http']
        bundle = calibre / Path(http['frozenBundle']).relative_to(provider['rootPath'])
        assert read_hash(bundle, 134217728) == http['frozenBundleSha256'], 'BOOKS_CALIBRE_ARCHIVE'
        assert read_hash(hook / 'http/client.py', 262144) == http['patchedSha256'], 'BOOKS_CALIBRE_HTTP'
        assert read_hash(hook / 'site.py', 262144) == http['bootstrapSha256'], 'BOOKS_CALIBRE_BOOTSTRAP'
        assert json.loads((hook / 'http-framing.json').read_text()) == http, 'BOOKS_CALIBRE_MANIFEST'
        assert all(stat.S_IMODE(folder.stat().st_mode) == 0o555 for folder in [hook, hook / 'http']), 'BOOKS_CALIBRE_ROOT_MODE'
        assert all(stat.S_IMODE(path.stat().st_mode) == 0o444 for path in [hook / 'site.py', hook / 'http/client.py', hook / 'http-framing.json']), 'BOOKS_CALIBRE_FILE_MODE'
        libraries = provider['stdlib']
        assert libraries['schemaVersion'] == 1 and libraries['pythonVersion'] == http['pythonVersion'], 'BOOKS_CALIBRE_STDLIB_API'
        assert read_hash(hook / 'stdlib.json', libraries['limits']['manifestBytes']), 'BOOKS_CALIBRE_STDLIB_MANIFEST_TYPE'
        assert json.loads((hook / 'stdlib.json').read_text()) == libraries, 'BOOKS_CALIBRE_STDLIB_MANIFEST'
        for entry in libraries['modules'].values():
            target = hook / entry['file']
            assert target.stat().st_size == entry['bytes'] and read_hash(target, libraries['limits']['fileBytes']) == entry['sha256'], 'BOOKS_CALIBRE_STDLIB_SOURCE'
            assert stat.S_IMODE(target.stat().st_mode) == 0o444, 'BOOKS_CALIBRE_STDLIB_MODE'
        assert stat.S_IMODE((hook / 'stdlib.json').stat().st_mode) == 0o444, 'BOOKS_CALIBRE_STDLIB_MANIFEST_MODE'
        native_ssl = provider['nativeSsl']
        assert native_ssl['schemaVersion'] == 1 and native_ssl['spec']['rootPath'] == provider['rootPath'], 'BOOKS_CALIBRE_SSL_API'
        guard = calibre / native_ssl['spec']['proofDirectory'] / 'guard.py'
        assert read_hash(guard, 16384) == native_ssl['spec']['guardSha256'], 'BOOKS_CALIBRE_SSL_GUARD'
        namespace = {'__name__': 'books_calibre_ssl'}
        exec(compile(guard.read_bytes(), str(guard), 'exec', optimize=0), namespace)
        namespace['installed'](native_ssl['spec'], calibre)
        native_socket = provider['nativeSocket']
        assert native_socket['schemaVersion'] == 1 and native_socket['spec']['paths']['root'] == provider['rootPath'], 'BOOKS_CALIBRE_SOCKET_API'
        socket_spec = native_socket['spec']
        guard = calibre / Path(socket_spec['paths']['proof']).relative_to(provider['rootPath']) / 'guard.py'
        assert read_hash(guard, socket_spec['limits']['guardBytes']) == socket_spec['guardSha256'], 'BOOKS_CALIBRE_SOCKET_GUARD'
        namespace = {'__name__': 'books_calibre_socket'}
        exec(compile(guard.read_bytes(), str(guard), 'exec', optimize=0), namespace)
        namespace['installed'](socket_spec, calibre)

    def apply_request_options(spec, app):
        files = app_files(app)
        assert distribution(files) == spec['app']['sourceDistributionSha256'], 'BOOKS_APP_PATCH_TREE_SOURCE'
        entry = spec['app']['requestOptions']
        path = app / entry['path']
        assert not Path(entry['path']).is_absolute() and '..' not in Path(entry['path']).parts, 'BOOKS_APP_PATCH_PATH'
        raw = path.read_bytes()
        assert digest(raw) == entry['sourceSha256'], 'BOOKS_APP_PATCH_SOURCE'
        text = raw.decode()
        assert text.count(entry['old']) == entry['count'] == 3, 'BOOKS_APP_PATCH_COUNT'
        output = text.replace(entry['old'], entry['new']).encode()
        assert digest(output) == entry['patchedSha256'], 'BOOKS_APP_PATCH_RESULT'
        compile(output, str(path), 'exec')
        expected = dict(files)
        expected[entry['path']] = files[entry['path']] | {'sha256': digest(output), 'bytes': len(output)}
        assert distribution(expected) == spec['app']['patchedDistributionSha256'], 'BOOKS_APP_PATCH_TREE_RESULT'
        cache = list(itertools.islice((path.parent / '__pycache__').glob(path.stem + '.*.pyc'), 9))
        assert len(cache) <= 8, 'BOOKS_APP_BYTECODE_BOUND'
        # Image-local, non-retriable operation. Validate every guard before writes.
        path.write_bytes(output)
        for bytecode in cache:
            bytecode.unlink()
        assert distribution(app_files(app)) == spec['app']['patchedDistributionSha256'], 'BOOKS_APP_PATCH_WRITE'

    def metadata(path):
        output = subprocess.check_output(['dpkg-deb', '-f', str(path), 'Package', 'Version', 'Architecture'], timeout=10)
        assert len(output) <= 8192, 'BOOKS_NATIVE_METADATA_BOUND'
        fields = dict(line.split(': ', 1) for line in output.decode().splitlines())
        return {'name': fields['Package'], 'version': fields['Version'], 'architecture': fields['Architecture']}

    if __name__ == '__main__':
        try:
            mode, manifest, app, *roots = sys.argv[1:]
            value = json.loads(Path(manifest).read_text())
            if mode == value['commands']['verify']:
                assert len(roots) == 3, 'BOOKS_VERIFY_PORTS'
                versions = {name: importlib.metadata.version(name) for name in value['pythonPackages']}
                verify(value, Path(app), *map(Path, roots), sys.version.split()[0], versions, metadata)
            else:
                assert mode == value['commands']['apply'] and not roots, 'BOOKS_PATCH_PORTS'
                apply_request_options(value, Path(app))
        except Exception as error:
            print(str(error) if isinstance(error, AssertionError) else 'BOOKS_RUNTIME_INPUT_INVALID', file=sys.stderr)
            sys.exit(1)
  '';
  guardSource = pkgs.writeText "books-runtime-input-guard.py" guard;
  manifestSource = pkgs.writeText "books-runtime.json" (builtins.toJSON spec);
  inputIdentity = builtins.hashString "sha256" (builtins.toJSON spec + guard);
  debPaths = lib.concatMapStringsSep " " (entry: "/tmp/hwc-books/native/${entry.filename}") nativePackages;
  runtime = helpers.mkRuntimeImage {
    name = "books";
    version = "schema${toString spec.app.databaseVersion}-python${spec.pythonVersion}";
    recipe = ''
      FROM ${spec.sourceImage} AS app-source
      FROM ${assets.image} AS calibre-source
      FROM ${spec.baseImage}
      # Qualified inputs ${inputIdentity}
      ENV ${lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "${name}=${lib.escapeShellArg value}") environment)}
      RUN test ! -e ${assets.rootPath} && test ! -e ${assets.http.rootPath} && test ! -e /app/calibre
      COPY --from=app-source /app/lazylibrarian/ /tmp/hwc-books-app/
      COPY --from=app-source /defaults/version.txt /defaults/version.txt
      COPY --from=calibre-source ${assets.rootPath}/ ${assets.rootPath}/
      COPY --from=calibre-source ${assets.http.rootPath}/ ${assets.http.rootPath}/
      COPY inputs/ /tmp/hwc-books/
      # COPY creates the destination root as 0755; restore the donor hook's
      # immutable directory modes before its input guard validates them.
      RUN chmod 0555 ${assets.http.rootPath} ${assets.http.rootPath}/http
      RUN echo '${spec.app.versionMarkerSha256}  /defaults/version.txt' | sha256sum -c -
      RUN python3 -B /tmp/hwc-books/guard.py ${spec.commands.verify} /tmp/hwc-books/manifest.json /tmp/hwc-books-app /tmp/hwc-books/native ${assets.rootPath} ${assets.http.rootPath}
      RUN dpkg --unpack ${debPaths} && dpkg --configure --pending && test -z "$(dpkg --audit)" && mkdir /tmp/hwc-books-empty-sources && touch /tmp/hwc-books-empty.list && apt-get -o Dir::Etc::sourcelist=/tmp/hwc-books-empty.list -o Dir::Etc::sourceparts=/tmp/hwc-books-empty-sources check
      RUN rm -rf /app/lazylibrarian && mv /tmp/hwc-books-app /app/lazylibrarian && ln -s ${assets.rootPath} /app/calibre
      RUN python3 -B /tmp/hwc-books/guard.py ${spec.commands.apply} /tmp/hwc-books/manifest.json /app/lazylibrarian
    '' + framing.recipe + config.system.build.calibreRuntimeSystemPythonRecipe.text + ''
      RUN buildTmp=$(mktemp -d /tmp/hwc-books-calibre.XXXXXX) && trap 'rm -rf "$buildTmp"' EXIT && export CALIBRE_CONFIG_DIRECTORY="$buildTmp/config" XDG_CACHE_HOME="$buildTmp/cache" && ${assets.rootPath}/calibre_postinstall && calibre-debug --version && calibredb --version && ebook-convert --version && ebook-meta --version
      RUN rm -rf /tmp/hwc-books /tmp/hwc-books-empty.list /tmp/hwc-books-empty-sources
    '';
  };
  runtimeContext = pkgs.runCommand "books-runtime-context" {} ''
    mkdir -p "$out/inputs/native"
    cp -r ${config.system.build.calibreRuntimeSystemPythonContext} "$out/system-python"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${manifestSource} "$out/inputs/manifest.json"
    cp ${guardSource} "$out/inputs/guard.py"
    ${lib.concatMapStringsSep "\n" (entry:
      "cp ${pkgs.fetchurl { inherit (entry) url; sha256 = entry.sha256; name = entry.filename; }} \"$out/inputs/native/${entry.filename}\"") nativePackages}
  '';
  runtimeBinding = pkgs.writeText "books-runtime-binding.json" (builtins.toJSON {
    schemaVersion = 1;
    image = runtime.image;
    inherit environment;
  });
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  options.hwc.media.books = {
    enable = lib.mkEnableOption "LazyLibrarian books management container";

    image = lib.mkOption {
      type = lib.types.str;
      default = runtime.image;
      description = "Prebuilt same-schema LazyLibrarian runtime with qualified native dependencies and Calibre assets";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPU support (not typically needed for LazyLibrarian)";
    };

    httpRoot = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        HTTP root path for reverse proxy. Empty is correct for the current
        name-based vhost (books.<vhostDomain>), where LazyLibrarian serves at
        root. A non-empty value makes it 404 everything at "/", so it must
        change in the same commit as the route mode, never before or after.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.booksRuntimeImageRecipe = runtime.dockerfile;
    system.build.booksRuntimeImageContext = runtimeContext;
    system.build.booksRuntimeInputGuard = guardSource;
    system.build.booksRuntimeBinding = runtimeBinding;
    systemd.services.podman-books.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
      ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
        echo "Prebuild Books from ${runtimeContext} before activation" >&2
        exit 1
      }
    '');
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [ {
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "The qualified Books runtime requires its x86_64 native inputs";
    } ] ++ helpers.mkVpnAssertions {
      name = "books";
      networkMode = cfg.network.mode;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    };
  };
}
