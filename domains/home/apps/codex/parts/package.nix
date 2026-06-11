# domains/home/apps/codex/parts/package.nix
#
# Codex CLI pinned from the upstream release binary (autoPatchelf'd).
# NOT the module default — the server intentionally uses stock pkgs.codex
# (stable channel). Machines that want this pin set:
#   hwc.home.apps.codex.package = pkgs.callPackage <this file> { };

{ stdenv, fetchurl, autoPatchelfHook, libcap, openssl, zlib, glibc, gnutar }:

stdenv.mkDerivation {
  pname = "codex";
  version = "0.101.0";
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libcap
    openssl
    zlib
    stdenv.cc.cc.lib
    glibc
  ];
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v0.101.0/codex-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "sha256-6XMt47hw32o5zkukRplhDvWBhDlneTRX+O8R86WlgjY=";
  };
  dontUnpack = true;
  installPhase = ''
    install -d "$out/bin"
    ${gnutar}/bin/tar -xf "$src" -C "$out/bin"
    mv "$out/bin/codex-x86_64-unknown-linux-gnu" "$out/bin/codex"
    chmod 755 "$out/bin/codex"
  '';
  meta.mainProgram = "codex";
}
