{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Python runtime
    python312
    python312Packages.pip
    python312Packages.hatchling

    # Development tools
    python312Packages.pytest
    python312Packages.pytest-cov
    ruff

    # Google API dependencies (system packages for faster builds)
    python312Packages.google-api-python-client
    python312Packages.google-auth
    python312Packages.google-auth-oauthlib
    python312Packages.requests
  ];

  shellHook = ''
    # Create virtualenv if it doesn't exist
    if [ ! -d .venv ]; then
      echo "Creating virtual environment..."
      python -m venv .venv
    fi

    # Activate virtualenv
    source .venv/bin/activate

    # Install package in editable mode
    pip install -e ".[dev]" --quiet

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mailbot Development Shell"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Available commands:"
    echo "    mailbot --help              Run the CLI tool"
    echo "    pytest                      Run tests"
    echo "    ruff check src/             Lint code"
    echo "    ruff format src/            Format code"
    echo ""
    echo "  Google OAuth Setup:"
    echo "    1. Get credentials.json from Google Cloud Console"
    echo "    2. Place in this directory (gitignored)"
    echo "    3. Run: mailbot --dry-run"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  '';
}
