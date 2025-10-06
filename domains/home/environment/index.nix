{ ... }: {
  imports = [
    ./options.nix
    ./shell/index.nix
    ./scripts/transcript-formatter.nix
    ./parts/development.nix
    ./parts/productivity.nix
  ];
}
