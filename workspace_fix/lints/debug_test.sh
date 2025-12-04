#!/usr/bin/env bash

# Debug script to see what's happening with the rg command
REPO_ROOT="/home/eric/.nixos"  # Adjust this to your actual repo root

echo "=== DEBUG: Testing rg command ==="
echo "REPO_ROOT: $REPO_ROOT"
echo "Checking directory: $REPO_ROOT/domains/home/"

if [[ -d "$REPO_ROOT/domains/home/" ]]; then
    echo "Directory exists"
    
    echo "=== Raw rg output ==="
    rg --color=never -l "writeScriptBin" "$REPO_ROOT/domains/home/" 2>/dev/null
    
    echo "=== Captured in variable ==="
    writeScriptResults=$(rg --color=never -l "writeScriptBin" "$REPO_ROOT/domains/home/" 2>/dev/null || true)
    echo "Variable content: '$writeScriptResults'"
    echo "Variable length: ${#writeScriptResults}"
    
    if [[ -n "$writeScriptResults" ]]; then
        echo "=== Processing with while loop ==="
        while IFS= read -r filepath; do
            echo "Processing filepath: '$filepath'"
            if [[ -n "$filepath" ]]; then
                relative_path="${filepath#$REPO_ROOT/}"
                echo "  Relative path: $relative_path"
            fi
        done <<< "$writeScriptResults"
    else
        echo "Variable is empty!"
    fi
else
    echo "Directory does not exist!"
fi
