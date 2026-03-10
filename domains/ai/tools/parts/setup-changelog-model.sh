#!/usr/bin/env bash
# Setup the changelog-writer custom Ollama model
# Run this once after Ollama is available, or after updating the modelfile

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELFILE="$SCRIPT_DIR/changelog-writer.modelfile"
OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://localhost:11434}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }

# Check Ollama is available
if ! curl -s --connect-timeout 3 "$OLLAMA_ENDPOINT/api/tags" &>/dev/null; then
    log_error "Ollama not available at $OLLAMA_ENDPOINT"
    log_error "Start Ollama first: sudo systemctl start podman-ollama"
    exit 1
fi

# Check base model exists
if ! curl -s "$OLLAMA_ENDPOINT/api/tags" | jq -e '.models[] | select(.name | startswith("qwen2.5-coder:3b"))' &>/dev/null; then
    log_warn "Base model qwen2.5-coder:3b not found, pulling..."
    ollama pull qwen2.5-coder:3b
fi

# Check if modelfile exists
if [[ ! -f "$MODELFILE" ]]; then
    log_error "Modelfile not found: $MODELFILE"
    exit 1
fi

log_info "Building changelog-writer model..."

# Create the custom model
if ollama create changelog-writer -f "$MODELFILE"; then
    log_info "Model 'changelog-writer' created successfully"

    # Verify it works with a quick test
    log_info "Running quick test..."
    test_response=$(curl -s -X POST "$OLLAMA_ENDPOINT/api/generate" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "changelog-writer",
            "prompt": "Commit: \"feat(test): add foo configuration\"\nDiff: +foo = true;\nWrite changelog:",
            "stream": false,
            "options": {"num_predict": 30}
        }' | jq -r '.response // "FAILED"')

    echo "Test output: $test_response"

    if [[ "$test_response" != "FAILED" && -n "$test_response" ]]; then
        log_info "Model is working correctly"
    else
        log_warn "Model created but test failed - may need debugging"
    fi
else
    log_error "Failed to create model"
    exit 1
fi

echo ""
log_info "Setup complete! The readme-butler will now use 'changelog-writer' model."
