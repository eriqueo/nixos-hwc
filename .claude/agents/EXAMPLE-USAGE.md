# Script Quality Agent - Usage Examples

This document shows real examples of how to use the Script Quality Agent.

## Example 1: Creating a New Shell Script

### User Request
```
I need a shell script that:
1. Monitors a directory for new .mp3 files
2. Converts them to .opus format
3. Moves originals to archive directory
4. Logs all operations
5. Sends a notification when done
```

### Agent Response
The agent would:
1. Ask clarifying questions
2. Choose shell script (system operations heavy)
3. Generate complete, production-grade script
4. Include error handling for all operations
5. Provide testing instructions

### Resulting Script Quality
- Grade: A+ (95/100)
- Has `set -euo pipefail`
- All paths configurable
- Comprehensive error handling
- Progress logging
- Cleanup on exit

---

## Example 2: Refactoring Poor Quality Script

### Original Script (grebuild.sh - partial)
```bash
#!/usr/bin/env bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: grebuild \"commit message\""
    exit 1
fi

COMMIT_MESSAGE="$1"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "🚀 Starting grebuild..."
sudo git add .
sudo git commit -m "$COMMIT_MESSAGE"
sudo nixos-rebuild switch --flake .#hwc-server
sudo git push
```

### Agent Analysis
```
Quality Assessment: 40/100 (Grade D)

Critical Issues:
1. ❌ Missing 'u' and 'o' in set flags (only has -e)
   Impact: Undefined variables won't cause errors, pipelines can fail silently
   Fix: Change to `set -euo pipefail`

2. ❌ Unquoted variables ($1, $COMMIT_MESSAGE)
   Impact: Will break with commit messages containing spaces
   Fix: Quote all variable references

3. ❌ No error handling for individual commands
   Impact: If rebuild fails, script continues to push
   Fix: Check each command's exit status

4. ❌ Hard-coded flake target (#hwc-server)
   Impact: Not reusable for other hosts
   Fix: Make configurable

5. ❌ No function organization
   Impact: Hard to test, maintain, or extend
   Fix: Extract into functions

High Priority Issues:
6. ⚠️ Mutable variables should be readonly
7. ⚠️ No usage/help function
8. ⚠️ Exit codes not explicit

Would you like me to refactor this script? I can:
a) Fix everything at once
b) Fix critical issues only (1-5)
c) Show you the refactored version with explanations
d) Apply fixes incrementally
```

### Refactored Version (excerpt)
```bash
#!/usr/bin/env bash
set -euo pipefail

# Script: grebuild - Git commit + NixOS rebuild workflow
# Usage: grebuild "commit message" [--target hwc-server]

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_TARGET="hwc-server"

# Logging
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }

# Main workflow
main() {
    local commit_message="$1"
    local target="${2:-$DEFAULT_TARGET}"

    # Validate inputs
    [[ -z "$commit_message" ]] && {
        log_error "Missing commit message"
        show_usage
        exit 2
    }

    # Git operations
    log_info "Committing changes..."
    if ! sudo git add .; then
        log_error "Failed to stage changes"
        exit 1
    fi

    if ! sudo git commit -m "$commit_message"; then
        log_error "Failed to commit"
        exit 1
    fi

    # NixOS rebuild
    log_info "Rebuilding NixOS..."
    if ! sudo nixos-rebuild switch --flake ".#${target}"; then
        log_error "Rebuild failed - NOT pushing to remote"
        exit 1
    fi

    # Only push if rebuild succeeded
    log_info "Pushing to remote..."
    if ! sudo git push; then
        log_error "Push failed (but local changes applied)"
        exit 1
    fi

    log_info "✅ Complete!"
}

main "$@"
```

### Quality Improvement
- **Before:** 40/100 (Grade D)
- **After:** 95/100 (Grade A+)

### Changes Summary
1. ✅ Added complete error handling
2. ✅ Fixed all quoting issues
3. ✅ Made target configurable
4. ✅ Added function organization
5. ✅ Added readonly for constants
6. ✅ Added usage function
7. ✅ Explicit exit codes
8. ✅ Prevents push if rebuild fails

---

## Example 3: Code Review of Python Script

### Original Script
```python
#!/usr/bin/env python3
import os, json, time

spool = "/mnt/hot/events/sab.ndjson"
env = os.environ
payload = {
    "client": "sab",
    "time": int(time.time()),
    "status": env.get("SAB_PP_STATUS",""),
    "nzb_name": env.get("NZBNAME",""),
}
with open(spool,"a") as f:
    f.write(json.dumps(payload)+"\n")
```

### Agent Review
```
Quality Assessment: 30/100 (Grade D)

Issues Found:

Critical:
1. ❌ No error handling - will crash on file permission errors
2. ❌ Hard-coded path - not configurable
3. ❌ No proper exit code handling

High Priority:
4. ⚠️ Missing type hints
5. ⚠️ Using os instead of pathlib
6. ⚠️ No argparse (not a CLI, but should have main())
7. ⚠️ No docstring
8. ⚠️ Global variables instead of config

Medium Priority:
9. ℹ️ Could use dataclass for payload structure
10. ℹ️ No logging

Low Priority:
11. ℹ️ Multiple imports on one line (style)

Recommendations:
- Wrap in try/except for file operations
- Convert to use pathlib
- Add type hints
- Create proper main() function structure
- Make spool path configurable via environment
- Add logging instead of silent operation

Would you like me to refactor this to production quality?
```

### Refactored Version
```python
#!/usr/bin/env python3
"""
SABnzbd Post-Processing Hook

Writes download completion events to NDJSON spool file for
downstream processing by media-orchestrator.

Environment Variables:
    SAB_PP_STATUS: Post-processing status from SABnzbd
    NZBNAME: Name of the downloaded NZB
    SPOOL_FILE: Path to spool file (default: /mnt/hot/events/sab.ndjson)
"""

import os
import sys
import json
import time
import logging
from pathlib import Path
from typing import Dict, Any
from dataclasses import dataclass, asdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class DownloadEvent:
    """Download completion event."""
    client: str
    time: int
    status: str
    nzb_name: str

    @classmethod
    from_environment(cls) -> 'DownloadEvent':
        """Create event from SABnzbd environment variables."""
        return cls(
            client="sab",
            time=int(time.time()),
            status=os.getenv("SAB_PP_STATUS", ""),
            nzb_name=os.getenv("NZBNAME", "")
        )

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)


def write_event(event: DownloadEvent, spool_file: Path) -> None:
    """
    Write event to spool file.

    Args:
        event: Download event to write
        spool_file: Path to spool file

    Raises:
        PermissionError: If file cannot be written
        OSError: If other file operation fails
    """
    try:
        # Ensure parent directory exists
        spool_file.parent.mkdir(parents=True, exist_ok=True)

        # Append event as NDJSON
        with open(spool_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(event.to_dict()) + '\n')

        logger.info(f"Event written: {event.nzb_name}")

    except PermissionError as e:
        logger.error(f"Permission denied writing to {spool_file}: {e}")
        raise
    except OSError as e:
        logger.error(f"Failed to write to {spool_file}: {e}")
        raise


def main() -> int:
    """
    Main entry point.

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    try:
        # Get configuration
        spool_file = Path(os.getenv(
            "SPOOL_FILE",
            "/mnt/hot/events/sab.ndjson"
        ))

        # Create event from environment
        event = DownloadEvent.from_environment()

        # Validate event has required data
        if not event.nzb_name:
            logger.warning("NZBNAME not set - skipping event")
            return 0

        # Write event
        write_event(event, spool_file)

        return 0

    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

### Quality Improvement
- **Before:** 30/100 (Grade D)
- **After:** 100/100 (Grade A+)

### Changes Summary
1. ✅ Added comprehensive type hints
2. ✅ Converted to pathlib
3. ✅ Added proper error handling
4. ✅ Created structured main() function
5. ✅ Made spool path configurable
6. ✅ Added logging
7. ✅ Used dataclass for event structure
8. ✅ Added docstrings
9. ✅ Proper exit codes
10. ✅ Validates input data

---

## Example 4: Interactive Refactoring Session

### User
```
Can you review this script and suggest improvements incrementally?

[pastes script]
```

### Agent
```
I'll review this step by step. Let me start with the most critical issues:

Current Grade: 55/100 (Grade C)

Let's fix issues in priority order:

═══ PHASE 1: CRITICAL (Security & Correctness) ═══

Issue 1: Missing error handling
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Current code (line 23):
    result=$(curl https://api.example.com)

Problem: If curl fails, script continues with empty result

Fix:
    if ! result=$(curl https://api.example.com 2>&1); then
        log_error "API call failed: $result"
        exit 1
    fi

Would you like me to:
a) Show you all Phase 1 fixes
b) Apply this fix and test
c) Explain why this is critical
```

### User
```
a) Show all Phase 1 fixes
```

### Agent
```
═══ PHASE 1: CRITICAL FIXES (5 total) ═══

Fix 1: Add error handling to API calls (lines 23, 45, 67)
Fix 2: Quote all variables (12 instances found)
Fix 3: Add set -euo pipefail at top
Fix 4: Remove hard-coded credentials (line 18)
Fix 5: Add trap for cleanup (temp file at line 89)

Estimated impact: Grade will improve from 55 → 75 (C → B)

Would you like me to:
a) Apply all Phase 1 fixes now
b) Show fixes one at a time
c) See Phase 2 issues first (High Priority)
```

This interactive approach helps users:
- Understand what's being changed and why
- Learn best practices incrementally
- Control the pace of refactoring
- See the impact of each improvement

---

## Key Takeaways

1. **The agent is educational** - explains WHY, not just WHAT
2. **Provides grades and metrics** - quantifiable quality
3. **Offers choices** - user controls the process
4. **Incrementalimprovements** - can refactor step-by-step
5. **Production-ready output** - not just "good enough"

## Getting Started

```bash
# Copy the agent prompt
cat .claude/agents/script-quality-agent.md

# Then in Claude:
# 1. Paste the agent prompt
# 2. Say: "Please review this script: [paste script]"
# 3. Follow the agent's recommendations

# Or use Claude Code CLI:
claude --agent .claude/agents/script-quality-agent.md \
    "Review workspace/utilities/scripts/grebuild.sh"
```

Start with one script, see the improvement, then expand to others!
