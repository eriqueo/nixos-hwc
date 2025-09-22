#!/usr/bin/env nix-shell
#! nix-shell -i bash -p python3 python3Packages.requests python3Packages.watchdog python3Packages.tkinter

# NixOS-native Transcript Formatter Runner
# This script uses nix-shell to provide all dependencies

set -e

SCRIPT_DIR="$HOME/.nixos/scripts/transcript-formatter"
FORMATTER_SCRIPT="$SCRIPT_DIR/obsidian_transcript_formatter.py"
PROMPT_FILE="$SCRIPT_DIR/formatting_prompt.txt"

echo "🐧 NixOS Transcript Formatter"
echo "============================="

# Create script directory
mkdir -p "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

# Check if Qwen is running
echo "🤖 Checking Qwen connection..."
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Qwen/Ollama not running."
    echo "Please start it first:"
    echo "  ollama serve"
    echo "  ollama pull qwen2.5:7b"
    exit 1
fi

# Check required files
if [ ! -f "$FORMATTER_SCRIPT" ]; then
    echo "❌ Formatter script not found: $FORMATTER_SCRIPT"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# Create Obsidian directories
mkdir -p "$HOME/99-vaults/06-contractor/raw"

echo "✅ All dependencies loaded via nix-shell"
echo "🎯 Starting transcript formatter..."
echo "   Watching: $HOME/99-vaults/06-contractor/raw/"
echo ""

# Run the formatter (dependencies provided by nix-shell)
python3 "$FORMATTER_SCRIPT"

