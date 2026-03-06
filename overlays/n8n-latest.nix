# overlays/n8n-latest.nix
# Override n8n to latest version (2.x)

final: prev: {
  n8n = prev.n8n.overrideAttrs (oldAttrs: rec {
    version = "2.10.3";
    src = prev.fetchFromGitHub {
      owner = "n8n-io";
      repo = "n8n";
      rev = "n8n@${version}";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    # npmDepsHash will need updating - nix will tell us the correct hash
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  });
}
