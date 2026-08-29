{ stdenv, lib, fetchurl }:

stdenv.mkDerivation rec {
  pname   = "herdr";
  version = "0.8.2";

  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64";
    hash = "sha256-l2FQoU1JDJSyQ+ouGn6y37Z/EuNrGC25CTb2co5q7PQ=";
  };

  dontUnpack    = true;
  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Agent multiplexer that lives in your terminal (tmux for AI agents)";
    homepage    = "https://herdr.dev";
    license     = licenses.mit;
    platforms   = [ "x86_64-linux" ];
    mainProgram = "herdr";
  };
}
