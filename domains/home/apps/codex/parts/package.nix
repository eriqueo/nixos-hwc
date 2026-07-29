# domains/home/apps/codex/parts/package.nix
#
# Codex CLI pinned from the upstream release binary.
# NOT the module default — the server intentionally uses stock pkgs.codex
# (stable channel). Machines that want this pin set:
#   hwc.home.apps.codex.package = pkgs.callPackage <this file> { };
#
# 0.146.0 ships a static-pie musl binary (was dynamic -gnu through 0.101.0), so
# it has no dynamic deps — autoPatchelfHook and the glibc/openssl/zlib/libcap
# inputs the old build needed are gone. Bump: change version, the -musl URL, the
# sha256, and (if upstream renames it) the mv source below.

{ stdenv, fetchurl, gnutar }:

stdenv.mkDerivation {
  pname = "codex";
  version = "0.146.0";
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v0.146.0/codex-x86_64-unknown-linux-musl.tar.gz";
    sha256 = "sha256-W6O5QFVDlTCB9mHQhU0mb3biq75R1BNJNVo23nZzd2o=";
  };
  dontUnpack = true;
  installPhase = ''
    install -d "$out/bin"
    ${gnutar}/bin/tar -xf "$src" -C "$out/bin"
    mv "$out/bin/codex-x86_64-unknown-linux-musl" "$out/bin/codex"
    chmod 755 "$out/bin/codex"
  '';
  meta.mainProgram = "codex";
}
