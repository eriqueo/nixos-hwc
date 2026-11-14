{ stdenvNoCC, lib, fetchurl }:

# The static herdr-core release `hc update` and `hc machine add` install, from
# the same manifest (releases.herdr.dev/core/<version>/manifest.json). The
# binary is static-pie, so nothing is patched; `hc` is its other name.
stdenvNoCC.mkDerivation rec {
  pname = "herdr-core";
  version = "0.1.20";

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/herdr-core-linux-x86_64.tar.gz";
    hash = "sha256-rGuGiQxFGjdYRiCqpDi3G8DQvUMKLnwdfglfBSxBTnQ=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-core "$out/bin/herdr-core"
    ln -s herdr-core "$out/bin/hc"
    install -Dm644 -t "$out/share/doc/herdr-core" LICENSE THIRD-PARTY-NOTICES
    runHook postInstall
  '';

  meta = {
    description = "Herdr core (hc): terminals and coding agents that stay alive";
    homepage = "https://herdr.dev";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hc";
  };
}
