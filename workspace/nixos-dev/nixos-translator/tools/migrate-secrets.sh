#!/usr/bin/env bash
#
# Secrets Migration Script
# Runs ON the NixOS machine to decrypt agenix secrets and prepare for SOPS
#
# Usage:
#   ./migrate-secrets.sh \
#     --nixos-path /home/user/nixos-hwc \
#     --age-key /etc/age/keys.txt \
#     --output /tmp/secrets-export
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
NIXOS_PATH=""
AGE_KEY=""
OUTPUT_DIR=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Decrypt agenix secrets from NixOS and prepare for SOPS migration.

OPTIONS:
    --nixos-path PATH    Path to NixOS configuration directory
    --age-key PATH       Path to age private key (default: /etc/age/keys.txt)
    --output PATH        Output directory for decrypted secrets
    --dry-run            Show what would be done without executing
    -h, --help           Show this help message

EXAMPLE:
    sudo $0 \\
      --nixos-path /home/user/nixos-hwc \\
      --age-key /etc/age/keys.txt \\
      --output /tmp/secrets-export

NOTE: This script must run as root to access /etc/age/keys.txt
EOF
    exit 1
}

log() {
    echo -e "${GREEN}[migrate-secrets]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --nixos-path)
            NIXOS_PATH="$2"
            shift 2
            ;;
        --age-key)
            AGE_KEY="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate arguments
[[ -z "$NIXOS_PATH" ]] && error "Missing required argument: --nixos-path"
[[ -z "$OUTPUT_DIR" ]] && error "Missing required argument: --output"
[[ -z "$AGE_KEY" ]] && AGE_KEY="/etc/age/keys.txt"

# Validate paths
[[ ! -d "$NIXOS_PATH" ]] && error "NixOS path not found: $NIXOS_PATH"
[[ ! -f "$AGE_KEY" ]] && error "Age key not found: $AGE_KEY (run as root?)"

# Check for age binary
command -v age >/dev/null 2>&1 || error "age binary not found. Install with: nix-shell -p age"

log "NixOS path: $NIXOS_PATH"
log "Age key: $AGE_KEY"
log "Output directory: $OUTPUT_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE - No files will be modified"
fi

# Create output directory structure
mkdir -p "$OUTPUT_DIR"/{system,home,infrastructure,server,sops}

SECRETS_DIR="$NIXOS_PATH/domains/secrets/parts"

if [[ ! -d "$SECRETS_DIR" ]]; then
    error "Secrets directory not found: $SECRETS_DIR"
fi

log "Scanning for .age files in: $SECRETS_DIR"

# Find all .age files
AGE_FILES=$(find "$SECRETS_DIR" -type f -name "*.age")
TOTAL_FILES=$(echo "$AGE_FILES" | wc -l)

log "Found $TOTAL_FILES encrypted secret files"

# Decrypt each secret
DECRYPTED_COUNT=0
FAILED_COUNT=0

declare -A SECRETS_BY_CATEGORY

while IFS= read -r age_file; do
    # Get relative path from secrets/parts/
    rel_path="${age_file#$SECRETS_DIR/}"

    # Determine category from path
    category=$(echo "$rel_path" | cut -d'/' -f1)
    secret_name=$(basename "$age_file" .age)

    # Output path
    output_file="$OUTPUT_DIR/$category/$secret_name"

    log "Decrypting: $rel_path"

    if [[ "$DRY_RUN" == "false" ]]; then
        if age -d -i "$AGE_KEY" -o "$output_file" "$age_file" 2>/dev/null; then
            chmod 600 "$output_file"
            ((DECRYPTED_COUNT++))

            # Track for SOPS YAML generation
            SECRETS_BY_CATEGORY[$category]+="$secret_name "
        else
            warn "Failed to decrypt: $age_file"
            ((FAILED_COUNT++))
        fi
    else
        echo "  Would decrypt: $age_file -> $output_file"
        ((DECRYPTED_COUNT++))
        SECRETS_BY_CATEGORY[$category]+="$secret_name "
    fi
done <<< "$AGE_FILES"

log "Decrypted $DECRYPTED_COUNT secrets, $FAILED_COUNT failed"

# Generate SOPS YAML template
SOPS_YAML="$OUTPUT_DIR/sops/secrets.yaml.template"

log "Generating SOPS YAML template: $SOPS_YAML"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$SOPS_YAML" <<'YAML_HEADER'
# SOPS Secrets Template
#
# 1. Fill in all values (marked with REPLACE_WITH_ACTUAL_VALUE)
# 2. Rename to secrets.yaml
# 3. Encrypt with: sops -e -i secrets.yaml
#
# SOPS will encrypt only the values, leaving keys readable.

YAML_HEADER

    # Generate YAML structure
    for category in "${!SECRETS_BY_CATEGORY[@]}"; do
        echo "$category:" >> "$SOPS_YAML"

        for secret in ${SECRETS_BY_CATEGORY[$category]}; do
            # Try to read the decrypted value (first 50 chars for safety)
            secret_file="$OUTPUT_DIR/$category/$secret"
            if [[ -f "$secret_file" ]]; then
                # Don't output actual secret, just placeholder
                echo "  $secret: REPLACE_WITH_ACTUAL_VALUE  # See: $category/$secret" >> "$SOPS_YAML"
            fi
        done

        echo "" >> "$SOPS_YAML"
    done
fi

# Generate SOPS deployment script
DEPLOY_SCRIPT="$OUTPUT_DIR/sops/deploy-secrets.sh"

log "Generating SOPS deployment script: $DEPLOY_SCRIPT"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$DEPLOY_SCRIPT" <<'DEPLOY_HEADER'
#!/usr/bin/env bash
#
# Deploy SOPS secrets to /opt/secrets/
# Run this on the Arch machine after encrypting secrets.yaml with SOPS
#

set -euo pipefail

SECRETS_YAML="${1:-secrets.yaml}"
DEPLOY_DIR="/opt/secrets"

[[ ! -f "$SECRETS_YAML" ]] && echo "Error: $SECRETS_YAML not found" && exit 1

command -v sops >/dev/null 2>&1 || { echo "Error: sops not installed"; exit 1; }

echo "[deploy-secrets] Decrypting and deploying secrets from: $SECRETS_YAML"

# Create secrets directory
sudo mkdir -p "$DEPLOY_DIR"

DEPLOY_HEADER

    # Add deployment commands for each secret
    for category in "${!SECRETS_BY_CATEGORY[@]}"; do
        echo "# $category secrets" >> "$DEPLOY_SCRIPT"
        echo "sudo mkdir -p \"$DEPLOY_DIR/$category\"" >> "$DEPLOY_SCRIPT"

        for secret in ${SECRETS_BY_CATEGORY[$category]}; do
            cat >> "$DEPLOY_SCRIPT" <<DEPLOY_CMD
sops -d "\$SECRETS_YAML" | yq -r '.$category.$secret' | sudo tee "$DEPLOY_DIR/$category/$secret" >/dev/null
sudo chmod 440 "$DEPLOY_DIR/$category/$secret"
DEPLOY_CMD
        done

        echo "" >> "$DEPLOY_SCRIPT"
    done

    # Add group permissions
    cat >> "$DEPLOY_SCRIPT" <<'DEPLOY_FOOTER'

# Set ownership
sudo chown -R root:secrets "$DEPLOY_DIR"
sudo chmod 750 "$DEPLOY_DIR"

echo "[deploy-secrets] Secrets deployed successfully"
echo "[deploy-secrets] Verify with: sudo ls -la $DEPLOY_DIR"
DEPLOY_FOOTER

    chmod +x "$DEPLOY_SCRIPT"
fi

# Generate .sops.yaml configuration
SOPS_CONFIG="$OUTPUT_DIR/sops/.sops.yaml"

log "Generating SOPS config: $SOPS_CONFIG"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$SOPS_CONFIG" <<SOPS_CONFIG
# SOPS Configuration
# Place this file in your arch-hwc repository root

creation_rules:
  - path_regex: secrets\.yaml$
    age: >-
      REPLACE_WITH_YOUR_AGE_PUBLIC_KEY

# To get your age public key:
# age-keygen -y ~/.config/sops/age/keys.txt
SOPS_CONFIG
fi

# Generate summary report
SUMMARY="$OUTPUT_DIR/MIGRATION_SUMMARY.md"

log "Generating migration summary: $SUMMARY"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$SUMMARY" <<SUMMARY_HEADER
# Secrets Migration Summary

**Date:** $(date)
**Source:** $NIXOS_PATH
**Total Secrets:** $TOTAL_FILES
**Successfully Decrypted:** $DECRYPTED_COUNT
**Failed:** $FAILED_COUNT

## Secrets by Category

SUMMARY_HEADER

    for category in "${!SECRETS_BY_CATEGORY[@]}"; do
        count=$(echo "${SECRETS_BY_CATEGORY[$category]}" | wc -w)
        echo "- **$category**: $count secrets" >> "$SUMMARY"
    done

    cat >> "$SUMMARY" <<'SUMMARY_FOOTER'

## Next Steps

### 1. Set up SOPS on Arch machine

```bash
# Install SOPS
sudo pacman -S sops

# Generate age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt
```

### 2. Update .sops.yaml

Edit `sops/.sops.yaml` and replace `REPLACE_WITH_YOUR_AGE_PUBLIC_KEY` with your age public key.

### 3. Create secrets.yaml

Copy `sops/secrets.yaml.template` to `secrets.yaml` and fill in all values marked with `REPLACE_WITH_ACTUAL_VALUE`.

Use the decrypted files in this export directory as reference.

### 4. Encrypt with SOPS

```bash
sops -e -i secrets.yaml
```

### 5. Deploy to Arch machine

```bash
# Copy files to Arch machine
scp -r sops/ arch-machine:/tmp/

# On Arch machine
cd /tmp/sops
sudo ./deploy-secrets.sh secrets.yaml
```

### 6. Verify deployment

```bash
sudo ls -la /opt/secrets/
sudo cat /opt/secrets/system/user-initial-password  # Test one secret
```

### 7. Update docker-compose files

Update all `environment:` and `secrets:` references to point to `/opt/secrets/` paths.

### 8. Secure cleanup

```bash
# On NixOS machine (this export directory)
shred -uvz -n 3 *//*

# On Arch machine
shred -uvz -n 3 secrets.yaml  # After deploying
```

## Security Notes

- ⚠️ **IMPORTANT**: The decrypted secrets in this directory are PLAIN TEXT!
- Store this export on an encrypted volume
- Delete immediately after migration
- Never commit decrypted secrets to git
- Use secure methods to transfer between machines (encrypted USB, scp over VPN)

SUMMARY_FOOTER
fi

log "Migration export complete!"
echo ""
echo "📁 Output directory: $OUTPUT_DIR"
echo "📊 Summary: $SUMMARY"
echo "📜 SOPS template: $SOPS_YAML"
echo "🚀 Deploy script: $DEPLOY_SCRIPT"
echo ""
warn "The decrypted secrets are PLAIN TEXT! Handle with care."
echo ""
echo "Next: Read $SUMMARY for migration steps"
