#!/usr/bin/env bash
# Setup script to prevent losing unpushed commits

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Setting up auto-push protection..."

# Option 1: Post-commit hook (auto-push every commit)
cat > "$HOOKS_DIR/post-commit" <<'EOF'
#!/usr/bin/env bash
# Auto-push to prevent losing commits on SSH failures

BRANCH=$(git branch --show-current)
echo "Auto-pushing to $BRANCH..."

if git push origin "$BRANCH" 2>&1; then
    echo "✓ Pushed successfully"
else
    echo "⚠ Push failed - commits are LOCAL ONLY!"
    echo "Run: git push origin $BRANCH"
fi
EOF

chmod +x "$HOOKS_DIR/post-commit"

# Option 2: Cron job for periodic push (backup option)
CRON_SCRIPT="$REPO_ROOT/.claude/auto-push-cron.sh"
cat > "$CRON_SCRIPT" <<EOF
#!/usr/bin/env bash
cd "$REPO_ROOT"
BRANCH=\$(git branch --show-current)
UNPUSHED=\$(git log @{u}.. --oneline 2>/dev/null | wc -l)

if [ "\$UNPUSHED" -gt 0 ]; then
    echo "[\$(date)] Pushing \$UNPUSHED unpushed commits on \$BRANCH" | tee -a "$REPO_ROOT/.claude/auto-push.log"
    git push origin "\$BRANCH" 2>&1 | tee -a "$REPO_ROOT/.claude/auto-push.log"
fi
EOF

chmod +x "$CRON_SCRIPT"

echo ""
echo "✓ Post-commit auto-push hook installed"
echo ""
echo "Optional: Add this to your crontab for periodic backup pushes:"
echo "  */30 * * * * $CRON_SCRIPT"
echo ""
echo "To add to crontab: crontab -e"
