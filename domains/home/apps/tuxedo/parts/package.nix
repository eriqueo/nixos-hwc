# domains/home/apps/tuxedo/parts/package.nix
#
# tuxedo — prebuilt release binary (webstonehq/tuxedo, Rust).
#
# Pattern mirrors codex/herdr: fetch the upstream x86_64-linux release tarball
# and autoPatchelf it onto PATH. No cargoHash / Rust-2024 toolchain build, and
# no dependence on `tuxedo` landing in our pinned nixpkgs (only `tuxedo-rs`,
# the unrelated hardware daemon, is currently there).
#
# Upstream ships per-target tarballs + .sha256 sidecars:
#   https://github.com/webstonehq/tuxedo/releases
#
# To bump: change `version`, then refresh `sha256` with:
#   nix-prefetch-url https://github.com/webstonehq/tuxedo/releases/download/v<version>/tuxedo-v<version>-x86_64-unknown-linux-gnu.tar.gz
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  openssl,
}:
stdenv.mkDerivation rec {
  pname = "tuxedo";
  version = "2026.6.2";

  src = fetchurl {
    url = "https://github.com/webstonehq/tuxedo/releases/download/v${version}/tuxedo-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "1mh9gliz23piv4sk6lzz4js06qyz8vr4xdrkjfbhj2bvrhkbpf9i";
  };

  nativeBuildInputs = [autoPatchelfHook];

  # glibc + libgcc_s come from stdenv. These cover the common extra needs of a
  # Rust release binary; autoPatchelf fails loudly naming any still-missing lib,
  # so add here only what it reports.
  buildInputs = [stdenv.cc.cc.lib zlib openssl];

  # Release is a bare tarball, not a Nix-style source tree.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p unpacked "$out/bin"
    tar -xf "$src" -C unpacked
    # Locate the binary regardless of whether the archive is flat or nested.
    bin="$(find unpacked -type f -name tuxedo | head -n1)"
    if [ -z "$bin" ]; then
      echo "tuxedo: binary not found in release archive. Contents:" >&2
      find unpacked -maxdepth 3 -type f >&2
      exit 1
    fi
    install -m755 "$bin" "$out/bin/tuxedo"
    runHook postInstall
  '';

  meta = {
    description = "Fast, keyboard-driven terminal UI for todo.txt";
    homepage = "https://github.com/webstonehq/tuxedo";
    platforms = ["x86_64-linux"];
    mainProgram = "tuxedo";
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    # license = lib.licenses.<confirm upstream license>;
  };
}
