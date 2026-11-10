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
    ./generate-domain-readmes.py --check --domain home

    # Show detailed report
    ./generate-domain-readmes.py --check --verbose
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Optional
from dataclasses import dataclass

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verification.charter import README_SECTIONS, readme_requirements


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

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.domains_dir = repo_root / "domains"
        self.requirements = readme_requirements(repo_root)

    def find_all_domains(self) -> List[DomainInfo]:
        return [DomainInfo(path=path, name=path.name,
                           level="domain" if sections else "module",
                           parent_domain=None if sections else path.relative_to(self.domains_dir).parts[0])
                for path, sections in self.requirements.items()]

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

        required = self.requirements[domain.path]
        missing = [section for section in required
                   if not any(found.startswith(section) for found in sections)]

        is_valid = len(missing) == 0

        # Gather extra info
        extra_info = {
            "sections_found": len(sections),
            "all_sections": sorted(sections),
        }

        return ValidationResult(
            domain=domain,
            readme_exists=readme_exists,
            missing_sections=missing,
            extra_info=extra_info,
            is_valid=is_valid,
        )

    def generate_readme(self, domain: DomainInfo) -> str:
        entries = sorted(path.name + ("/" if path.is_dir() else "")
                         for path in domain.path.iterdir() if path.name != "README.md")
        structure = "\n".join(entries)
        return f"""# {domain.name}

## Purpose

[Describe the capability.]

## Boundaries

[State what this owner manages and link to related owners.]

## Structure

```text
{structure}
```

## Changelog

- [Describe the change and date.]
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
                with readme_path.open("x") as output:
                    output.write(content)
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
        help="Filter to specific domain (e.g., 'home' or 'home/apps/firefox')",
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
