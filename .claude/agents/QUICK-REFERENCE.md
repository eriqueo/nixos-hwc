# Script Quality Quick Reference

## Shell Script Checklist

### Essential Header
```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Template Structure
```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Functions
log_error() { echo "[ERROR] $*" >&2; }

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

cleanup() {
    # Cleanup code here
    :
}
trap cleanup EXIT

main() {
    # Main logic here
    :
}

main "$@"
```

### Common Patterns

**Variable Quoting**
```bash
✅ echo "$variable"
❌ echo $variable

✅ path="$HOME/directory"
❌ path=$HOME/directory
```

**Temporary Files**
```bash
✅ tmp_file=$(mktemp)
   trap 'rm -f "$tmp_file"' EXIT
❌ tmp_file="/tmp/myfile.$$"
```

**Dependency Checking**
```bash
check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || error_exit "Missing: ${missing[*]}"
}

check_dependencies git curl jq
```

**Array Handling**
```bash
files=("file1.txt" "file2.txt" "file with spaces.txt")
for file in "${files[@]}"; do
    echo "$file"
done
```

**File Processing with Null Delimiter**
```bash
find /path -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    echo "$file"
done
```

---

## Python Script Checklist

### Essential Structure
```python
#!/usr/bin/env python3
"""Module docstring."""

import sys
from pathlib import Path
from typing import List, Dict, Optional

def main() -> int:
    """Main entry point."""
    try:
        # Logic here
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

### Type Hints
```python
def process_file(path: Path, max_lines: int = 100) -> List[str]:
    """Process file and return lines."""
    ...

def get_config(config_path: Path) -> Dict[str, Any]:
    """Load configuration."""
    ...

def find_files(directory: Path, pattern: str = "*.txt") -> List[Path]:
    """Find matching files."""
    ...
```

### pathlib Usage
```python
✅ from pathlib import Path
   config = Path("/etc/app/config.yaml")
   if config.exists():
       content = config.read_text()

❌ import os
   config = "/etc/app/config.yaml"
   if os.path.exists(config):
       with open(config) as f:
           content = f.read()
```

### Error Handling
```python
try:
    result = risky_operation()
except FileNotFoundError as e:
    logger.error(f"File not found: {e}")
    return 1
except PermissionError as e:
    logger.error(f"Permission denied: {e}")
    return 1
except Exception as e:
    logger.error(f"Unexpected error: {e}")
    raise
```

### CLI with argparse
```python
import argparse

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Script description")
    parser.add_argument('-i', '--input', type=Path, required=True)
    parser.add_argument('-o', '--output', type=Path)
    parser.add_argument('-v', '--verbose', action='store_true')
    return parser.parse_args()
```

### Class-Based Design
```python
@dataclass
class Config:
    """Configuration container."""
    input_path: Path
    output_path: Optional[Path] = None
    verbose: bool = False

class Processor:
    """Main processing class."""

    def __init__(self, config: Config):
        self.config = config
        self.logger = logging.getLogger(__name__)

    def process(self) -> int:
        """Run processing."""
        try:
            # Logic here
            return 0
        except Exception as e:
            self.logger.error(f"Processing failed: {e}")
            return 1
```

### Security
```python
# Subprocess
✅ subprocess.run(["git", "status"], check=True)
❌ subprocess.run("git status", shell=True)  # DANGEROUS!

# YAML
✅ config = yaml.safe_load(f)
❌ config = yaml.load(f)  # DANGEROUS!
```

---

## Grading Scale

| Score | Grade | Description |
|-------|-------|-------------|
| 90-100 | A+ | Production-ready, exemplary code |
| 80-89 | A | Very good, minor improvements possible |
| 70-79 | B | Good, some issues need addressing |
| 60-69 | C | Acceptable, multiple improvements needed |
| 40-59 | D | Poor, significant refactoring required |
| 0-39 | F | Failing, complete rewrite recommended |

---

## Common Issues & Fixes

### Issue: Script fails silently
```bash
❌ #!/bin/bash
✅ #!/usr/bin/env bash
   set -euo pipefail
```

### Issue: Variables not quoted
```bash
❌ rm -rf $TEMP_DIR
✅ rm -rf "$TEMP_DIR"
```

### Issue: Hard-coded paths
```bash
❌ CONFIG="/etc/myapp/config"
✅ readonly CONFIG="${MYAPP_CONFIG:-/etc/myapp/config}"
```

### Issue: No error checking
```bash
❌ result=$(curl https://api.example.com)
   echo $result

✅ if ! result=$(curl https://api.example.com 2>&1); then
       log_error "API call failed: $result"
       exit 1
   fi
   echo "$result"
```

### Issue: Missing type hints (Python)
```python
❌ def process(data):
       return data.upper()

✅ def process(data: str) -> str:
       """Convert data to uppercase."""
       return data.upper()
```

### Issue: Using os.path (Python)
```python
❌ import os
   file = os.path.join(os.getcwd(), "data.txt")
   if os.path.exists(file):
       with open(file) as f:
           content = f.read()

✅ from pathlib import Path
   file = Path.cwd() / "data.txt"
   if file.exists():
       content = file.read_text()
```

---

## Testing Checklist

Before deploying any script:

- [ ] Test with valid input
- [ ] Test with invalid/missing input
- [ ] Test with files containing spaces in names
- [ ] Test with empty files
- [ ] Test with missing dependencies
- [ ] Test error paths (what if command fails?)
- [ ] Test as non-root user (if applicable)
- [ ] Test cleanup (temp files removed?)
- [ ] Test help/usage output
- [ ] Test logging output

---

## When to Use What

**Use Shell Script When:**
- Simple file operations
- System administration tasks
- Glue between existing commands
- Quick automation
- <100 lines of logic

**Use Python When:**
- Complex data processing
- API interactions
- Need data structures (dicts, lists)
- >100 lines of logic
- Need libraries (requests, yaml, etc.)

**Use Both When:**
- Shell script as entry point
- Python for heavy lifting
- Example: Shell validates, Python processes

---

## Agent Invocation

```bash
# Quick review
claude --agent .claude/agents/script-quality-agent.md "Review script.sh"

# Create new script
claude --agent .claude/agents/script-quality-agent.md \
    "Create a shell script that monitors /var/log for errors"

# Refactor existing
claude --agent .claude/agents/script-quality-agent.md \
    "Refactor workspace/utilities/scripts/grebuild.sh"
```

---

## Resources

- **Shell Style Guide:** https://google.github.io/styleguide/shellguide.html
- **ShellCheck:** https://www.shellcheck.net/
- **Python Type Hints:** https://docs.python.org/3/library/typing.html
- **PEP 8:** https://pep8.org/

---

**Remember:** Quality code is code that works correctly, handles errors gracefully, and can be maintained by others (including future you).
