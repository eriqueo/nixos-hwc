{ ... }: {
  imports = [
    ./options.nix
    ./shell/index.nix
    ./scripts/transcript-formatter.nix
    ./parts/development.nix
    ./productivity.nix
  ];
}
