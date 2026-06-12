#!/usr/bin/env bash
# readme-freshness.sh — detect domain READMEs that are older than the
# code they describe (Law-12 drift detector).
#
# Stdout: machine-parseable STALE lines, one per stale README.
# Stderr: a final summary line.
# Exit:   0 = no stale READMEs, 1 = at least one stale, 2 = usage error.

set -u

usage() {
    cat <<'EOF'
Usage: readme-freshness.sh [-h|--help]

Scans every domains/**/README.md tracked in git and reports any whose most
recent commit is older than the most recent commit touching other tracked
files in the same directory.

Output (stdout, one line per stale README):
  STALE <dir> content=<short-hash> <YYYY-MM-DD> readme=<short-hash> <YYYY-MM-DD>

Summary (stderr):
  STALE: <n> / <total> domain READMEs

Exit codes:
  0  no stale READMEs found
  1  at least one stale README found
  2  usage error
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) usage >&2; exit 2 ;;
esac

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "readme-freshness: must be run inside a git repository" >&2
    exit 2
fi

total=0
stale=0

while IFS= read -r readme; do
    [ -z "$readme" ] && continue
    dir="${readme%/README.md}"

    content_ct="$(git log -1 --format='%ct' -- "$dir" ":(exclude)$dir/README.md" 2>/dev/null)"
    if [ -z "$content_ct" ]; then
        # Nothing else in this dir is tracked — cannot be stale.
        continue
    fi

    readme_ct="$(git log -1 --format='%ct' -- "$readme" 2>/dev/null)"
    if [ -z "$readme_ct" ]; then
        # README untracked or never committed — skip rather than crash.
        continue
    fi

    total=$((total + 1))

    if [ "$content_ct" -gt "$readme_ct" ]; then
        content_meta="$(git log -1 --format='%h %ad' --date=short -- "$dir" ":(exclude)$dir/README.md")"
        readme_meta="$(git log -1 --format='%h %ad' --date=short -- "$readme")"
        content_hash="${content_meta%% *}"
        content_date="${content_meta##* }"
        readme_hash="${readme_meta%% *}"
        readme_date="${readme_meta##* }"
        printf 'STALE %s content=%s %s readme=%s %s\n' \
            "$dir" "$content_hash" "$content_date" "$readme_hash" "$readme_date"
        stale=$((stale + 1))
    fi
done < <(git ls-files 'domains/**/README.md')

printf 'STALE: %d / %d domain READMEs\n' "$stale" "$total" >&2

if [ "$stale" -gt 0 ]; then
    exit 1
fi
exit 0
