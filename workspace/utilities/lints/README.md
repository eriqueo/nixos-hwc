# Linting Scripts

This directory contains automated linting and validation scripts for maintaining code quality and Charter compliance across the nixos-hwc infrastructure.

## Available Lints

### Charter Compliance Lint
**Script**: `charter-lint.sh`
**Purpose**: Validate adherence to CHARTER.md architectural rules
**Usage**: `./scripts/lints/charter-lint.sh`
**Reports**: `.lint-reports/charter-lint-*.txt`

**Checks**:
- Namespace alignment with folder structure
- Module anatomy (index.nix, options.nix, sys.nix, parts/)
- Anti-patterns (HM in profiles, mixed-domain modules)
- Lane purity (Home Manager vs NixOS separation)

### Container Consistency Lint
**Script**: `container-lint.sh`
**Purpose**: Validate NixOS container configurations for consistency, security, and troubleshootability
**Usage**: `./scripts/lints/container-lint.sh [--verbose] [container-name]`
**Reports**: `.lint-reports/container-lint-*.txt`

**Checks**:
- File structure (index.nix, options.nix, sys.nix/parts/config.nix)
- Charter v6 compliance (assertions, validation, comments)
- Networking configuration (network modes, dependencies, port bindings)
- Caddy integration (routes, URL base configuration)
- Resource limits (memory, CPU)
- Environment variables (PUID, PGID, TZ, URL base)
- Secrets handling (agenix integration, no hardcoded passwords)

**Examples**:
```bash
# Validate all containers
./scripts/lints/container-lint.sh

# Validate specific container with verbose output
./scripts/lints/container-lint.sh --verbose sonarr

# Validate all *arr containers
./scripts/lints/container-lint.sh ".*arr"
```

**Output**:
- 🟢 **[PASS]**: Check passed
- 🟡 **[WARN]**: Warning (best practice violation, not critical)
- 🔴 **[ERROR]**: Error (Charter violation, missing critical configuration)

## Validation Workflow

### When to Run Lints

1. **Before committing changes**: Ensure your changes maintain Charter compliance
2. **After adding new containers**: Validate new container follows patterns
3. **During refactoring**: Track progress of migration projects
4. **CI/CD integration**: Automated checks on pull requests (future)

### Recommended Workflow

```bash
# 1. Make changes to container configuration
vim domains/server/containers/sonarr/sys.nix

# 2. Run container lint for that specific container
./scripts/lints/container-lint.sh sonarr

# 3. Fix any errors/warnings
# ...

# 4. Run full container lint
./scripts/lints/container-lint.sh

# 5. Run charter lint to ensure no Charter violations
./scripts/lints/charter-lint.sh

# 6. Commit changes
git add .
git commit -m "refactor(sonarr): migrate to Charter v6 pattern"
```

## Understanding Lint Results

### Exit Codes
- **0**: All checks passed (or only warnings)
- **1**: Validation errors found (must fix before merge)
- **2**: Script error (check usage)

### Interpreting Warnings vs Errors

**Errors (must fix)**:
- Missing required files (index.nix, options.nix)
- Charter violations (namespace mismatch, missing assertions)
- Security issues (hardcoded secrets)
- Broken dependencies (VPN mode without Gluetun dependency)

**Warnings (should fix)**:
- Missing optional files (parts/lib.nix, parts/scripts.nix)
- Best practices (section headers, documentation comments)
- Consistency issues (network mode hardcoded)
- Optimization opportunities (missing resource limits)

## Creating New Lints

To add a new lint script:

1. **Create the script**:
   ```bash
   touch scripts/lints/my-new-lint.sh
   chmod +x scripts/lints/my-new-lint.sh
   ```

2. **Follow the pattern**:
   - Use consistent color codes (RED, YELLOW, GREEN, BLUE, CYAN)
   - Implement counters (ERRORS, WARNINGS, PASSED)
   - Save reports to `.lint-reports/`
   - Exit with appropriate codes (0=pass, 1=fail, 2=error)

3. **Document it**:
   - Add section to this README
   - Include usage examples
   - Explain what it checks and why

4. **Test thoroughly**:
   - Test with valid configurations
   - Test with invalid configurations
   - Test edge cases (empty files, missing directories)

## Lint Report History

Lint reports are saved to `.lint-reports/` with timestamps:
- `charter-lint-YYYYMMDD-HHMMSS.txt`
- `container-lint-YYYYMMDD-HHMMSS.txt`

**Tracking Progress**:
```bash
# View latest container lint report
cat .lint-reports/container-lint-*.txt | tail -n 50

# Compare error counts over time
grep "Errors:" .lint-reports/container-lint-*.txt

# Find all containers with specific issue
grep -r "missing assertions" .lint-reports/container-lint-*.txt
```

## Integration with Development Workflow

### Pre-commit Hooks (Future)
```bash
# .git/hooks/pre-commit
#!/bin/bash
./scripts/lints/charter-lint.sh || exit 1
./scripts/lints/container-lint.sh || exit 1
```

### CI/CD Checks (Future)
```yaml
# .github/workflows/lint.yml
- name: Run Charter Lint
  run: ./scripts/lints/charter-lint.sh

- name: Run Container Lint
  run: ./scripts/lints/container-lint.sh
```

## Troubleshooting

### Lint script fails to run
**Error**: `Permission denied`
**Fix**: `chmod +x scripts/lints/*.sh`

### False positives
**Issue**: Script reports errors for valid configurations
**Fix**:
1. Check if your configuration uses a newer pattern
2. Update the lint script to handle the new pattern
3. Add comments in code to explain deviations

### Missing containers
**Issue**: Script doesn't detect a container
**Fix**:
1. Ensure container directory is in `domains/server/containers/`
2. Ensure directory doesn't start with `_` (reserved for shared utilities)
3. Check that `index.nix` imports the container

## Related Documentation

- **CHARTER.md**: Architectural rules and principles
- **docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md**: Detailed container analysis
- **docs/architecture/compliance-lint.md**: Charter compliance tracking
- **docs/DOCUMENTATION_STANDARDS.md**: Documentation requirements

## Contributing

When adding new validation checks:
1. Ensure the check is based on Charter requirements or documented best practices
2. Provide clear, actionable error messages
3. Distinguish between errors (must fix) and warnings (should fix)
4. Add verbose mode output for detailed debugging
5. Update this README with the new check
