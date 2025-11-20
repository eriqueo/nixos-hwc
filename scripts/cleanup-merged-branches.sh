#!/bin/bash
# Branch Cleanup Script
# These branches have been verified as fully merged into main
# Created: 2025-11-20
# Safe to delete: 8 branches

echo "========================================"
echo "Cleaning up merged branches..."
echo "========================================"
echo ""
echo "The following branches are fully merged into main:"
echo "  - claude/fix-session-crashes-01HdoKQdRMb1SrMrKEybfJRi"
echo "  - claude/audit-script-quality-01BGbjfS9hnc12mv8bqaefV5"
echo "  - claude/local-ai-overhaul-01CVadz9JTpQ4auavQvFWsdd"
echo "  - claude/audit-dotfiles-nixos-01RXuwtS4QSfMGXDGjfJqx5i"
echo "  - claude/frigate-hardware-acceleration-01FurseZNKWmDKBzxZsE8veN"
echo "  - claude/immich-nix-storage-setup-01HYhJLcji1cL4DAD2cEs1EB"
echo "  - claude/rebuild-ai-bible-0125ahAKgvSnuag8zDjJpZHU"
echo "  - claude/agents-skills-workflows-01EEa8CKMsr8CZYTjyXe56Vn"
echo ""
echo "Deleting remote branches..."
echo ""

git push origin --delete \
  claude/fix-session-crashes-01HdoKQdRMb1SrMrKEybfJRi \
  claude/audit-script-quality-01BGbjfS9hnc12mv8bqaefV5 \
  claude/local-ai-overhaul-01CVadz9JTpQ4auavQvFWsdd \
  claude/audit-dotfiles-nixos-01RXuwtS4QSfMGXDGjfJqx5i \
  claude/frigate-hardware-acceleration-01FurseZNKWmDKBzxZsE8veN \
  claude/immich-nix-storage-setup-01HYhJLcji1cL4DAD2cEs1EB \
  claude/rebuild-ai-bible-0125ahAKgvSnuag8zDjJpZHU \
  claude/agents-skills-workflows-01EEa8CKMsr8CZYTjyXe56Vn

if [ $? -eq 0 ]; then
  echo ""
  echo "========================================"
  echo "✅ Cleanup complete!"
  echo "========================================"
else
  echo ""
  echo "========================================"
  echo "⚠️  Some branches failed to delete"
  echo "This may be due to permissions or"
  echo "the branches may already be deleted"
  echo "========================================"
fi
