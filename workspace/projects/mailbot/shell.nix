{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    python311Full
    python311Packages.pip
    python311Packages.virtualenv
  ];
  shellHook = ''
    export WORKSPACE="$HOME/.nixos/workspace"
    echo "Dev shell ready. Run: python -m pip install -e ."
  '';
}
