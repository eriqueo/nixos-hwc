#!/usr/bin/env bash
# domains/business/morning-briefing/run-dispatch.sh
#
# Today-queue agent dispatch runner. Processes prompt cards queued by
# hwc_today's `agent` verb (output/dispatch/*.md — each card is a PRE-WRITTEN,
# Eric-approved prompt with its REPORT_PATH in a header comment) through a
# READ-ONLY headless claude run, and writes the report where the card says.
#
# v1 is deliberately read-only: the allowlist below grants file reads, search,
# and read-only shell (journalctl / systemctl status / git log / podman ps).
# No Edit, no Write tool (the report is written by THIS script from stdout),
# no state-changing bash. Widening this allowlist is a decision, not a patch —
# see the proven-not-claimed law in the charter before you do.
#
# Triggered by the today-dispatch.path unit (DirectoryNotEmpty on dispatch/).
set -uo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_DIR="${AGENT_DIR}/output/dispatch"
# done/ must live OUTSIDE dispatch/ — the path unit triggers on
# DirectoryNotEmpty(dispatch/), and a nested done/ would re-arm it forever.
DONE_DIR="${AGENT_DIR}/output/dispatch-done"
REPORTS_DIR="${AGENT_DIR}/output/reports"
LOG_FILE="${AGENT_DIR}/logs/dispatch.log"
CLAUDE_BIN="${CLAUDE_BIN:-/etc/profiles/per-user/eric/bin/claude}"

log() { echo "[$(date '+%F %T')] $*" >> "${LOG_FILE}"; }

mkdir -p "${DONE_DIR}" "${REPORTS_DIR}" "$(dirname "${LOG_FILE}")"

# Read-only tool grant. Bash patterns are prefix-matched by the CLI.
ALLOWED_TOOLS="Read,Glob,Grep,Bash(journalctl:*),Bash(systemctl status:*),Bash(systemctl list-units:*),Bash(systemctl list-timers:*),Bash(df:*),Bash(du:*),Bash(podman ps:*),Bash(podman logs:*),Bash(git log:*),Bash(git show:*),Bash(git diff:*),Bash(rg:*),Bash(ls:*),Bash(cat:*),Bash(head:*),Bash(tail:*),Bash(curl -s:*)"

shopt -s nullglob
for card in "${DISPATCH_DIR}"/*.md; do
  name="$(basename "${card}")"
  report_path="$(grep -m1 -oP '(?<=REPORT_PATH: ).*(?= -->)' "${card}" || true)"
  if [ -z "${report_path}" ]; then
    report_path="${REPORTS_DIR}/${name%.md}.md"
  fi
  log "dispatch: ${name} → ${report_path}"

  # One shot, read-only, 10-minute budget. stdout IS the report.
  if output=$(timeout 600 "${CLAUDE_BIN}" -p \
      --allowedTools "${ALLOWED_TOOLS}" \
      --output-format text \
      < "${card}" 2>>"${LOG_FILE}"); then
    printf '%s\n\n---\n*dispatched %s · card: %s*\n' "${output}" "$(date -Iseconds)" "${name}" > "${report_path}"
    mv "${card}" "${DONE_DIR}/${name}"
    log "OK: ${name} ($(wc -l < "${report_path}") lines)"
  else
    log "ERROR: claude run failed for ${name} — card left in queue for retry"
  fi
done

# Sweep non-card strays (an agent scratch file, a partial write): anything
# left that isn't a queued .md card keeps DirectoryNotEmpty armed and makes
# the path unit re-fire this runner forever. Quarantine, don't delete.
for stray in "${DISPATCH_DIR}"/*; do
  [ -e "${stray}" ] || continue
  case "${stray}" in *.md) continue ;; esac
  mv "${stray}" "${DONE_DIR}/stray-$(basename "${stray}")"
  log "WARN: quarantined stray ${stray##*/} from dispatch/"
done
