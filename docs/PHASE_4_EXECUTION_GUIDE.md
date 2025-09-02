# PHASE_4_EXECUTION_GUIDE.md — Test & Documentation

Goal: prove the architecture works end-to-end on every machine; validate security and Charter compliance; generate final documentation.

## 4.1 Prereqs
  ./scripts/validate-charter-v4.sh
  rg "home-manager\.extraSpecialArgs.*nixosConfig\s*=\s*config" profiles/
Both must pass.

## 4.2 Machine Build Tests
List machines, build each, capture logs, scan errors:
  find machines/ -name "config.nix" | sed 's|machines/||; s|/config.nix||' > machines.list
  while read m; do
    time nixos-rebuild test --flake .#hwc-$m 2>&1 | tee build-test-$m.log
    rg -i "error|warning" build-test-$m.log
  done < machines.list

## 4.3 Service Functionality Checks
Generate service inventory:
  find modules/services/ -name "*.nix" -exec basename {} .nix \; | sort > docs/SERVICE_LIST.txt
For each service:
  sudo systemctl status podman-SERVICE_NAME.service 2>/dev/null || sudo systemctl status SERVICE_NAME.service
If networked, verify port:
  curl -f http://localhost:PORT || echo "not responding"
Logs:
  journalctl -u "*SERVICE_NAME*" --since="5 minutes ago" --no-pager

## 4.4 Security & Path Validation
- No cleartext secrets in repo
- `age`/agenix present where required
- No hardcoded `/mnt/*`; all service paths via `config.hwc.paths.*`
- Only permitted paths (`/etc`, `/var`, `/tmp`) when routed through options

Commands:
  rg -n "password\s*=\s*\".+\"" modules/ machines/ profiles/
  rg -n "age\.secrets" modules/
  rg -n "/etc/|/var/|/tmp/" modules/ | rg -v "hwc\.paths|/nix/store"
  rg -n "/mnt/" modules/ machines/ profiles/ | rg -v "hwc\.paths"

## 4.5 Final Validation Harness
  ./scripts/full-system-test.sh 2>&1 | tee docs/FINAL_VALIDATION_LOG.txt
Must exit 0 and log shows green builds for all machines.

## 4.6 Documentation Artifacts
Produce and commit:
- docs/ARCHITECTURE_OVERVIEW.md
- docs/USAGE_PATTERNS.md
- docs/TROUBLESHOOTING.md
- docs/MIGRATION_RETROSPECTIVE.md
- docs/FINAL_VALIDATION_LOG.txt
- scripts/full-system-test.sh (executable)

## Completion Criteria (Phase 4)
- All machines: test builds clean; services start and respond as expected
- Security checks clean; no `/mnt` violations
- Final validation harness passes
- Documentation present, accurate, and committed
