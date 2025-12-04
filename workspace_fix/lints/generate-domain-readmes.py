#!/usr/bin/env python3
"""
Domain README Generator and Validator

Validates that all domains have READMEs with required sections.
Can generate skeleton READMEs based on the template.
Designed for CI validation and developer assistance.

Usage:
    # Validate all domain READMEs
    ./generate-domain-readmes.py --check

    # Generate missing READMEs (dry run)
    ./generate-domain-readmes.py --generate --dry-run

    # Generate missing READMEs (write files)
    ./generate-domain-readmes.py --generate

    # Validate specific domain
    ./generate-domain-readmes.py --check --domain infrastructure

    # Show detailed report
    ./generate-domain-readmes.py --check --verbose
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass


@dataclass
class DomainInfo:
    """Information about a domain directory"""
    path: Path
    name: str
    level: str  # "domain" or "module"
    parent_domain: Optional[str] = None


@dataclass
class ValidationResult:
    """Result of README validation"""
    domain: DomainInfo
    readme_exists: bool
    missing_sections: List[str]
    extra_info: Dict[str, any]
    is_valid: bool


class DomainREADMEValidator:
    """Validates and generates domain README files"""

    # Required sections for domain-level READMEs
    DOMAIN_REQUIRED_SECTIONS = [
        "Purpose & Scope",
        "Domain Architecture",
        "Domain Boundaries",
    ]

    # Required sections for module-level READMEs
    MODULE_REQUIRED_SECTIONS = [
        "Overview",
        "Configuration",
    ]

    # Common sections (recommended but not required)
    RECOMMENDED_SECTIONS = [
        "Module Standards",
        "Best Practices",
        "Development Workflow",
        "Troubleshooting",
    ]

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.domains_dir = repo_root / "domains"
        self.template_path = repo_root / "docs" / "templates" / "DOMAIN_README_TEMPLATE.md"

    def find_all_domains(self) -> List[DomainInfo]:
        """Find all domain directories (domains/* and domains/*/*)"""
        domains = []

        # Level 1: Top-level domains (domains/*)
        for domain_dir in self.domains_dir.iterdir():
            if domain_dir.is_dir() and not domain_dir.name.startswith("."):
                domains.append(DomainInfo(
                    path=domain_dir,
                    name=domain_dir.name,
                    level="domain",
                ))

                # Level 2: Sub-domain modules (domains/*/*)
                for subdir in domain_dir.iterdir():
                    if subdir.is_dir() and not subdir.name.startswith("."):
                        # Skip common non-module directories
                        if subdir.name in ["core", "parts", "apps"]:
                            # Look for modules inside these
                            for module_dir in subdir.iterdir():
                                if module_dir.is_dir() and not module_dir.name.startswith("."):
                                    domains.append(DomainInfo(
                                        path=module_dir,
                                        name=module_dir.name,
                                        level="module",
                                        parent_domain=domain_dir.name,
                                    ))
                        else:
                            domains.append(DomainInfo(
                                path=subdir,
                                name=subdir.name,
                                level="module",
                                parent_domain=domain_dir.name,
                            ))

        return domains

    def extract_sections(self, readme_path: Path) -> Set[str]:
        """Extract section headings from a README file"""
        if not readme_path.exists():
            return set()

        with open(readme_path) as f:
            content = f.read()

        # Extract h2 headers (## Section Name)
        sections = set()
        for match in re.finditer(r'^##\s+(.+)$', content, re.MULTILINE):
            section = match.group(1).strip()
            # Remove emoji and extra formatting
            section = re.sub(r'[✅❌🔗🔧⚙️🎨🐚⌨️🌊📊🖥️🌐]', '', section).strip()
            sections.add(section)

        return sections

    def validate_readme(self, domain: DomainInfo) -> ValidationResult:
        """Validate a domain's README"""
        readme_path = domain.path / "README.md"
        readme_exists = readme_path.exists()

        if not readme_exists:
            return ValidationResult(
                domain=domain,
                readme_exists=False,
                missing_sections=[],
                extra_info={"error": "README.md not found"},
                is_valid=False,
            )

        # Extract sections from README
        sections = self.extract_sections(readme_path)

        # Determine required sections based on level
        required = (
            self.DOMAIN_REQUIRED_SECTIONS
            if domain.level == "domain"
            else self.MODULE_REQUIRED_SECTIONS
        )

        # Check for missing sections (case-insensitive, partial match)
        missing = []
        for req_section in required:
            found = any(
                req_section.lower() in section.lower()
                for section in sections
            )
            if not found:
                missing.append(req_section)

        is_valid = len(missing) == 0

        # Gather extra info
        extra_info = {
            "sections_found": len(sections),
            "all_sections": sorted(sections),
        }

        # Check for recommended sections
        recommended_found = [
            rec for rec in self.RECOMMENDED_SECTIONS
            if any(rec.lower() in s.lower() for s in sections)
        ]
        extra_info["recommended_found"] = recommended_found

        return ValidationResult(
            domain=domain,
            readme_exists=readme_exists,
            missing_sections=missing,
            extra_info=extra_info,
            is_valid=is_valid,
        )

    def generate_readme(self, domain: DomainInfo) -> str:
        """Generate a skeleton README for a domain"""
        if domain.level == "domain":
            return self._generate_domain_readme(domain)
        else:
            return self._generate_module_readme(domain)

    def _generate_domain_readme(self, domain: DomainInfo) -> str:
        """Generate a domain-level README"""
        domain_name = domain.name.capitalize()

        return f"""# {domain_name} Domain

## Purpose & Scope

**The {domain_name} Domain** provides [primary purpose]. This domain manages [what it manages] and handles [what it handles].

**Key Principle**: If it's [decision criteria] → {domain.name} domain.

## Domain Architecture

The {domain.name} domain follows [architectural pattern] with **[organizing principle]**:

```
domains/{domain.name}/
├── index.nix                    # Domain aggregator
├── core/                        # Essential {domain.name} functionality
├── [category]/                  # [Category description]
└── parts/                       # Shared {domain.name} components
```

## Domain Boundaries

### ✅ **This Domain Manages**
- [Responsibility 1]: [Detailed description]
- [Responsibility 2]: [Detailed description]

### ❌ **This Domain Does NOT Manage**
- [Not responsible 1]: → Goes to `domains/[other-domain]/`
- [Not responsible 2]: → Goes to `domains/[other-domain]/`

### 🔗 **Integration Points**
- **Consumes from**: `domains/[dependency1]/`
- **Provides to**: `domains/[consumer1]/`

## Module Standards

### Standard Module Structure
```
domains/{domain.name}/[category]/[module]/
├── index.nix                   # Main implementation
├── options.nix                 # API definition (REQUIRED)
├── sys.nix                     # System-lane integration (if needed)
└── parts/                      # Implementation details
```

### Option Namespace Pattern
```nix
# domains/{domain.name}/[category]/[module]/options.nix
options.hwc.{domain.name}.[category].[module] = {{
  enable = mkEnableOption "[Module description]";
  # Module-specific options
}};
```

## Best Practices

### ✅ **Do**
- **[Practice 1]**: [Detailed explanation]
- **Follow Charter**: Maintain compliance with HWC Charter v6.0

### ❌ **Don't**
- **[Anti-pattern 1]**: [Why not and what to do instead]

## Development Workflow

### Adding New Modules
1. **Create module directory**: `mkdir -p domains/{domain.name}/[category]/[module]/`
2. **Follow module standards**: Create `index.nix`, `options.nix`, `parts/config.nix`
3. **Define namespace**: `hwc.{domain.name}.[category].[module].*`
4. **Add to aggregator**: Include in `domains/{domain.name}/[category]/index.nix`

### Testing Changes
```bash
# Build domain changes
sudo nixos-rebuild build --flake .#hwc-[machine]

# Test specific module
nix eval .#nixosConfigurations.hwc-[machine].config.hwc.{domain.name}.[module].enable
```

## Validation & Troubleshooting

### Verify Configuration
```bash
# Check domain module status
nix eval .#nixosConfigurations.hwc-[machine].config.hwc.{domain.name}

# Check for conflicts
nixos-rebuild build --flake .#hwc-[machine] --show-trace
```

## Reference Links

- **Charter**: `CHARTER.md` - Complete HWC architecture
- **Template**: `docs/templates/DOMAIN_README_TEMPLATE.md`
- **Related Domains**:
  - `domains/[related]/README.md` - [Relationship]

---

**Charter Compliance**: v6.0
**Last Updated**: [Generate date with: date +%Y-%m-%d]
"""

    def _generate_module_readme(self, domain: DomainInfo) -> str:
        """Generate a module-level README"""
        module_name = domain.name.capitalize()
        parent = domain.parent_domain or "[domain]"

        return f"""# {module_name} Module

**Charter v6.0 Compliant Module**
**Namespace**: `hwc.{parent}.[category].{domain.name}.*`
**Location**: `domains/{parent}/[category]/{domain.name}/`

---

## Overview

{module_name} provides [description of what this module does].

**Key Features:**
- [Feature 1]
- [Feature 2]
- [Feature 3]

## Architecture

### Module Structure

```
domains/{parent}/[category]/{domain.name}/
├── index.nix              # Main entry point
├── options.nix            # API declarations
├── parts/
│   ├── config.nix        # Core configuration
│   └── [other].nix       # Additional parts
└── README.md             # This file
```

### Dependencies

```nix
hwc.[dependency1]           # [Why needed]
hwc.[dependency2]           # [Why needed]
```

## Configuration

### Basic Setup

```nix
# machines/[machine]/config.nix
hwc.{parent}.[category].{domain.name} = {{
  enable = true;
  # Basic options here
}};
```

### Advanced Configuration

```nix
hwc.{parent}.[category].{domain.name} = {{
  enable = true;

  # Advanced options
  [option1] = [value];
  [option2] = [value];
}};
```

## Common Operations

### Starting/Stopping
```bash
# Check status
systemctl status [service-name]

# Restart
sudo systemctl restart [service-name]
```

### Viewing Logs
```bash
# Service logs
journalctl -u [service-name] -f
```

## Troubleshooting

### Common Issues

**Issue 1**: [Description]
- **Solution**: [How to fix]

**Issue 2**: [Description]
- **Solution**: [How to fix]

### Validation
```bash
# Verify module configuration
nix eval .#nixosConfigurations.hwc-[machine].config.hwc.{parent}.[category].{domain.name}

# Build with trace
sudo nixos-rebuild build --flake .#hwc-[machine] --show-trace
```

## Reference Links

- **Parent Domain**: `domains/{parent}/README.md`
- **Charter**: `CHARTER.md`
- **Template**: `docs/templates/DOMAIN_README_TEMPLATE.md`

---

**Charter Compliance**: v6.0
**Last Updated**: [date]
"""

    def run_validation(
        self,
        check_only: bool = True,
        generate: bool = False,
        dry_run: bool = False,
        verbose: bool = False,
        domain_filter: Optional[str] = None,
    ) -> int:
        """Run validation and optionally generate READMEs"""
        domains = self.find_all_domains()

        if domain_filter:
            domains = [d for d in domains if domain_filter in str(d.path)]

        print(f"Found {len(domains)} domain/module directories")
        print()

        results = []
        for domain in domains:
            result = self.validate_readme(domain)
            results.append(result)

        # Report results
        invalid_count = sum(1 for r in results if not r.is_valid)
        missing_count = sum(1 for r in results if not r.readme_exists)

        if check_only:
            self._print_validation_report(results, verbose)

        if generate:
            self._generate_missing_readmes(results, dry_run)

        # Exit code
        if check_only and invalid_count > 0:
            print(f"\n❌ FAILED: {invalid_count} domain(s) have invalid or missing READMEs")
            return 1
        elif check_only:
            print(f"\n✅ PASSED: All domain READMEs are valid")
            return 0

        return 0

    def _print_validation_report(self, results: List[ValidationResult], verbose: bool):
        """Print validation report"""
        # Group by domain level
        domain_results = [r for r in results if r.domain.level == "domain"]
        module_results = [r for r in results if r.domain.level == "module"]

        print("=" * 80)
        print("DOMAIN README VALIDATION REPORT")
        print("=" * 80)

        print("\n📁 TOP-LEVEL DOMAINS")
        print("-" * 80)
        for result in domain_results:
            self._print_result(result, verbose)

        print("\n📦 DOMAIN MODULES")
        print("-" * 80)
        for result in module_results:
            self._print_result(result, verbose)

        # Summary
        total = len(results)
        valid = sum(1 for r in results if r.is_valid)
        invalid = total - valid
        missing = sum(1 for r in results if not r.readme_exists)

        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(f"Total: {total}")
        print(f"Valid: {valid} ✅")
        print(f"Invalid: {invalid} ❌")
        print(f"Missing: {missing} 📄")

    def _print_result(self, result: ValidationResult, verbose: bool):
        """Print individual validation result"""
        domain = result.domain
        rel_path = domain.path.relative_to(self.repo_root)

        if result.is_valid:
            status = "✅"
        elif not result.readme_exists:
            status = "📄"
        else:
            status = "❌"

        print(f"{status} {rel_path}")

        if not result.readme_exists:
            print(f"   → README.md not found")
        elif result.missing_sections:
            print(f"   → Missing sections: {', '.join(result.missing_sections)}")

        if verbose and result.readme_exists:
            sections = result.extra_info.get("all_sections", [])
            print(f"   → Sections: {', '.join(sections[:5])}" + (
                f" ... ({len(sections)} total)" if len(sections) > 5 else ""
            ))

    def _generate_missing_readmes(self, results: List[ValidationResult], dry_run: bool):
        """Generate README files for domains that don't have them"""
        missing = [r for r in results if not r.readme_exists]

        if not missing:
            print("✅ No missing READMEs to generate")
            return

        print(f"\n{'[DRY RUN] ' if dry_run else ''}Generating {len(missing)} missing README(s):")
        print()

        for result in missing:
            domain = result.domain
            readme_path = domain.path / "README.md"
            rel_path = readme_path.relative_to(self.repo_root)

            content = self.generate_readme(domain)

            if dry_run:
                print(f"Would create: {rel_path}")
                if result.domain.level == "domain":
                    print(f"  Type: Domain-level README")
                else:
                    print(f"  Type: Module-level README")
            else:
                readme_path.write_text(content)
                print(f"✅ Created: {rel_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Validate and generate domain README files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate existing READMEs (default mode)",
    )

    parser.add_argument(
        "--generate",
        action="store_true",
        help="Generate missing READMEs",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without writing files",
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed validation information",
    )

    parser.add_argument(
        "--domain",
        type=str,
        help="Filter to specific domain (e.g., 'infrastructure' or 'server/frigate')",
    )

    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Path to repository root (default: current directory)",
    )

    args = parser.parse_args()

    # Default to check mode if no mode specified
    if not args.check and not args.generate:
        args.check = True

    # Validate repo structure
    repo_root = args.repo_root.resolve()
    domains_dir = repo_root / "domains"

    if not domains_dir.exists():
        print(f"❌ Error: domains/ directory not found at {repo_root}")
        print(f"   Please run from repository root or specify --repo-root")
        return 1

    # Run validation
    validator = DomainREADMEValidator(repo_root)
    return validator.run_validation(
        check_only=args.check,
        generate=args.generate,
        dry_run=args.dry_run,
        verbose=args.verbose,
        domain_filter=args.domain,
    )


if __name__ == "__main__":
    sys.exit(main())
