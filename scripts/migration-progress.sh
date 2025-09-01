#!/usr/bin/env bash
# Charter v4 Migration Progress Tracker
# Shows current status and next actions

set -euo pipefail

echo "📊 Charter v4 Migration Progress"
echo "================================"

# Check current validation status
echo "🔍 Running Charter v4 validation..."
if ./scripts/validate-charter-v4.sh > /tmp/charter-validation.log 2>&1; then
    echo "✅ Charter v4 compliant - ready for Phase 2!"
    PHASE_1_COMPLETE=true
else
    echo "⚠️  Charter v4 violations found:"
    tail -10 /tmp/charter-validation.log | grep -E "(❌|⚠️)" || echo "   (see full output above)"
    PHASE_1_COMPLETE=false
fi

echo
echo "📋 Current Status:"
echo "- Phase 1 (Foundation): $([ "$PHASE_1_COMPLETE" = true ] && echo "✅ Complete" || echo "🚧 95% - violations remain")"
echo "- Phase 2 (Domain Cleanup): $([ "$PHASE_1_COMPLETE" = true ] && echo "🎯 Ready to start" || echo "⏸️  Waiting for Phase 1")"
echo "- Phase 3 (Validation): ⏸️  Waiting for Phase 2"

echo
echo "📖 Documentation:"
echo "- Migration Status: docs/MIGRATION_STATUS.md"
echo "- Charter v4: docs/CHARTER_v4.md" 
echo "- Claude Guidelines: CLAUDE.md"

echo
if [ "$PHASE_1_COMPLETE" = true ]; then
    echo "🎉 Phase 1 Complete - Ready for Phase 2!"
    echo "Next: Review service interdependencies and architecture cleanup"
else
    echo "🎯 Next Actions (Phase 1):"
    echo "1. Fix remaining violations (see validation output above)"
    echo "2. Run: ./scripts/add-section-headers.sh --all"
    echo "3. Address eric.nix system services issue"
    echo "4. Re-run this script to check progress"
fi

echo
echo "🔄 Process:"
echo "- Update docs/MIGRATION_STATUS.md after changes"
echo "- Run this script to check progress"
echo "- Commit with clear migration progress messages"