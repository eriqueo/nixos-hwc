#!/usr/bin/env python3
"""
CHARTER v8 Drift Analyzer - Domain/Profile/Module Correctness Audit

Detects architectural drift, redundancy, and misplaced scope across the
nixos-hwc repository using CHARTER rules as source of truth.

Usage:
    ./drift.py [path]              # Analyze specific path
    ./drift.py                     # Analyze entire repo

Output Format:
    CATEGORY | SEVERITY | FILE:LINE | MESSAGE

Categories:
    - MISPLACED_SCOPE: Code in wrong domain/profile/machine
    - REDUNDANCY: Multiple writers to same resource
    - MODULE_ANATOMY: Missing required files or structure
    - NAMING_DRIFT: Inconsistent naming patterns
    - SYS_COUPLING: sys.nix architectural violations

CHARTER References:
    - Section 3: Domain Boundaries
    - Section 4: Unit Anatomy
    - Section 6: Lane Purity
    - Section 13: Enforcement Rules
"""

import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Set, Tuple

# ANSI colors
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
GREEN = '\033[0;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
NC = '\033[0m'  # No Color


class DriftReport:
    """Collects and formats drift analysis results."""

    def __init__(self):
        self.issues: List[Tuple[str, str, str, str]] = []
        self.redundancy_groups: Dict[str, List[Tuple[str, int]]] = defaultdict(list)

    def add_issue(self, category: str, severity: str, location: str, message: str):
        """Add a drift issue."""
        self.issues.append((category, severity, location, message))

    def add_redundancy(self, resource_type: str, resource_id: str, file_path: str, line_num: int):
        """Track redundant resource declarations."""
        key = f"{resource_type}:{resource_id}"
        self.redundancy_groups[key].append((file_path, line_num))

    def print_issues(self):
        """Print all collected issues."""
        if not self.issues:
            print(f"{GREEN}No drift issues detected.{NC}")
            return

        # Sort by category, then severity
        severity_order = {"HIGH": 0, "MED": 1, "LOW": 2, "SUGGESTION": 3}
        sorted_issues = sorted(
            self.issues,
            key=lambda x: (x[0], severity_order.get(x[1], 99))
        )

        current_category = None
        for category, severity, location, message in sorted_issues:
            if category != current_category:
                print(f"\n{BLUE}=== {category} ==={NC}")
                current_category = category

            color = RED if severity == "HIGH" else YELLOW if severity == "MED" else CYAN
            print(f"{color}{category}{NC} | {severity} | {location} | {message}")

    def print_redundancy(self):
        """Print redundancy groups."""
        if not self.redundancy_groups:
            return

        print(f"\n{BLUE}=== REDUNDANCY GROUPS ==={NC}")

        for resource_key, locations in self.redundancy_groups.items():
            if len(locations) > 1:
                resource_type, resource_id = resource_key.split(":", 1)
                print(f"\n{RED}DUP_{resource_type}{NC} | HIGH | {resource_id} | {len(locations)} occurrences")
                for file_path, line_num in locations:
                    print(f"  → {file_path}:{line_num}")

    def has_issues(self) -> bool:
        """Check if any issues were found."""
        high_severity = any(sev == "HIGH" for _, sev, _, _ in self.issues)
        duplicates = any(len(locs) > 1 for locs in self.redundancy_groups.values())
        return high_severity or duplicates


class DriftAnalyzer:
    """Analyzes nixos-hwc repository for architectural drift."""

    def __init__(self, search_path: str = "."):
        self.search_path = Path(search_path).resolve()
        self.report = DriftReport()

    def analyze(self):
        """Run all drift analyses."""
        print("=" * 70)
        print("CHARTER v8 Drift Analyzer")
        print("=" * 70)
        print(f"\nAnalyzing: {self.search_path}\n")

        print(f"{BLUE}[1/6]{NC} Checking misplaced scope...")
        self.check_misplaced_scope()

        print(f"{BLUE}[2/6]{NC} Checking redundancy (multiple writers)...")
        self.check_redundancy()

        print(f"{BLUE}[3/6]{NC} Checking module anatomy...")
        self.check_module_anatomy()

        print(f"{BLUE}[4/6]{NC} Checking naming drift...")
        self.check_naming_drift()

        print(f"{BLUE}[5/6]{NC} Checking sys.nix coupling...")
        self.check_sys_coupling()

        print(f"{BLUE}[6/6]{NC} Checking profile structure...")
        self.check_profile_structure()

        print("\n" + "=" * 70)
        print("Drift Analysis Results")
        print("=" * 70)

        self.report.print_issues()
        self.report.print_redundancy()

        print("\n" + "=" * 70)
        print("Summary")
        print("=" * 70)

        if self.report.has_issues():
            print(f"{YELLOW}⚠️  Architectural drift detected{NC}")
            print("\nReview issues above and consider refactoring.")
            print("See CHARTER.md for architectural rules.")
            return 0  # drift is report-only, not fail
        else:
            print(f"{GREEN}✅ No significant drift detected{NC}")
            return 0

    def check_misplaced_scope(self):
        """
        Category 1: Misplaced scope violations
        CHARTER Section 3 (Domain Boundaries)
        """
        # Check profiles for implementation (should be feature menus)
        profiles_path = self.search_path / "profiles"
        if profiles_path.exists():
            for nix_file in profiles_path.glob("*.nix"):
                # Skip profiles/home.nix exception
                if nix_file.name == "home.nix":
                    continue

                content = nix_file.read_text()
                lines = content.split('\n')

                # Check for service implementations
                for i, line in enumerate(lines, 1):
                    if re.search(r'systemd\.services\.\w+\s*=\s*\{', line):
                        self.report.add_issue(
                            "MISPLACED_SCOPE", "HIGH",
                            f"{nix_file.relative_to(self.search_path)}:{i}",
                            "systemd service implementation in profile (profiles are menus, not implementation) (CHARTER §3)"
                        )

                    if re.search(r'virtualisation\.oci-containers\.containers\.\w+', line):
                        self.report.add_issue(
                            "MISPLACED_SCOPE", "HIGH",
                            f"{nix_file.relative_to(self.search_path)}:{i}",
                            "Container definition in profile (should be in domains/server) (CHARTER §3)"
                        )

        # Check machines for shared logic (should be in profiles/domains)
        machines_path = self.search_path / "machines"
        if machines_path.exists():
            for nix_file in machines_path.rglob("*.nix"):
                if nix_file.name in ["hardware.nix", "config.nix", "home.nix"]:
                    content = nix_file.read_text()

                    # Heuristic: large config blocks that should be in modules
                    if len(content) > 500:  # Arbitrary threshold
                        # Check for repeated patterns across machines
                        if re.search(r'(services\.\w+\s*=\s*\{[^}]{100,})', content):
                            self.report.add_issue(
                                "MISPLACED_SCOPE", "MED",
                                f"{nix_file.relative_to(self.search_path)}",
                                "Large service configuration in machine file (consider extracting to domain module) (CHARTER §3)"
                            )

    def check_redundancy(self):
        """
        Category 2: Redundancy / multiple writers
        CHARTER Section 13 (Single Source of Truth)
        """
        # Track port allocations
        port_usage: Dict[str, List[Tuple[Path, int]]] = defaultdict(list)

        # Track container names
        container_names: Dict[str, List[Tuple[Path, int]]] = defaultdict(list)

        # Track environment.etc paths
        etc_paths: Dict[str, List[Tuple[Path, int]]] = defaultdict(list)

        # Scan all .nix files
        for nix_file in self.search_path.rglob("*.nix"):
            content = nix_file.read_text()
            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                # Port detection
                port_matches = re.finditer(r'(?:ports?\s*=\s*\[?\s*|:)(\d{2,5})(?:["\s\];])', line)
                for match in port_matches:
                    port = match.group(1)
                    port_usage[port].append((nix_file, i))

                # Firewall ports
                fw_match = re.search(r'networking\.firewall\.allowed(?:TCP|UDP)Ports.*?(\d{2,5})', line)
                if fw_match:
                    port = fw_match.group(1)
                    port_usage[port].append((nix_file, i))

                # Container names
                container_match = re.search(r'virtualisation\.oci-containers\.containers\.([a-zA-Z0-9_-]+)', line)
                if container_match:
                    name = container_match.group(1)
                    container_names[name].append((nix_file, i))

                # environment.etc paths
                etc_match = re.search(r'environment\.etc\."?([^"{\s]+)"?', line)
                if etc_match:
                    path = etc_match.group(1)
                    etc_paths[path].append((nix_file, i))

        # Report redundant port usage
        for port, locations in port_usage.items():
            if len(locations) > 1:
                # Filter out duplicates from same file (could be legit in different contexts)
                unique_files = {loc[0] for loc in locations}
                if len(unique_files) > 1:
                    for file_path, line_num in locations:
                        self.report.add_redundancy(
                            "PORT", port,
                            str(file_path.relative_to(self.search_path)),
                            line_num
                        )

        # Report duplicate container names
        for name, locations in container_names.items():
            if len(locations) > 1:
                for file_path, line_num in locations:
                    self.report.add_redundancy(
                        "CONTAINER", name,
                        str(file_path.relative_to(self.search_path)),
                        line_num
                    )

        # Report duplicate etc paths
        for path, locations in etc_paths.items():
            if len(locations) > 1:
                for file_path, line_num in locations:
                    self.report.add_redundancy(
                        "ETC_PATH", path,
                        str(file_path.relative_to(self.search_path)),
                        line_num
                    )

    def check_module_anatomy(self):
        """
        Category 3: Module anatomy violations
        CHARTER Section 4 (Unit Anatomy)
        """
        domains_path = self.search_path / "domains"
        if not domains_path.exists():
            return

        # Find all module directories (dirs containing index.nix)
        for index_file in domains_path.rglob("index.nix"):
            module_dir = index_file.parent

            # Skip domain-level aggregators
            if module_dir.name in ["domains", "system", "home", "server", "infrastructure", "secrets"]:
                continue

            # Check for required options.nix
            options_file = module_dir / "options.nix"
            if not options_file.exists():
                self.report.add_issue(
                    "MODULE_ANATOMY", "HIGH",
                    str(module_dir.relative_to(self.search_path)),
                    "Missing required options.nix (CHARTER §4)"
                )

            # Check index.nix for section markers
            content = index_file.read_text()
            if "# OPTIONS" not in content:
                self.report.add_issue(
                    "MODULE_ANATOMY", "MED",
                    str(index_file.relative_to(self.search_path)),
                    "Missing # OPTIONS section marker (CHARTER §12)"
                )
            if "# IMPLEMENTATION" not in content:
                self.report.add_issue(
                    "MODULE_ANATOMY", "MED",
                    str(index_file.relative_to(self.search_path)),
                    "Missing # IMPLEMENTATION section marker (CHARTER §12)"
                )
            if "# VALIDATION" not in content and "enable" in content:
                self.report.add_issue(
                    "MODULE_ANATOMY", "MED",
                    str(index_file.relative_to(self.search_path)),
                    "Missing # VALIDATION section (modules with enable should assert dependencies) (CHARTER §20)"
                )

            # Check parts/ for impurity
            parts_dir = module_dir / "parts"
            if parts_dir.exists():
                for part_file in parts_dir.glob("*.nix"):
                    content = part_file.read_text()
                    lines = content.split('\n')

                    for i, line in enumerate(lines, 1):
                        # Check for options definitions (impure)
                        if re.search(r'^\s*options\.', line):
                            self.report.add_issue(
                                "MODULE_ANATOMY", "HIGH",
                                f"{part_file.relative_to(self.search_path)}:{i}",
                                "Options defined in parts/ (parts must be pure helpers) (CHARTER §11)"
                            )

                        # Check for config assignments (side effects)
                        if re.search(r'^\s*config\s*=', line):
                            self.report.add_issue(
                                "MODULE_ANATOMY", "HIGH",
                                f"{part_file.relative_to(self.search_path)}:{i}",
                                "Config assignment in parts/ (parts must be pure helpers) (CHARTER §11)"
                            )

    def check_naming_drift(self):
        """
        Category 4: Naming drift / inconsistent knobs
        CHARTER Section 12 (File Standards)
        """
        # Collect all option names from options.nix files
        option_patterns = defaultdict(list)

        for options_file in self.search_path.rglob("options.nix"):
            content = options_file.read_text()
            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                # Find option definitions
                opt_match = re.search(r'options\.hwc\.[a-zA-Z0-9.]+\.([a-zA-Z]+)\s*=', line)
                if opt_match:
                    opt_name = opt_match.group(1)

                    # Flag vague names
                    if opt_name in ['port', 'dir', 'path', 'config', 'data']:
                        self.report.add_issue(
                            "NAMING_DRIFT", "SUGGESTION",
                            f"{options_file.relative_to(self.search_path)}:{i}",
                            f"Vague option name '{opt_name}' (consider more specific: webPort, stateDir, configPath, etc.)"
                        )

                    # Track patterns for inconsistency detection
                    if opt_name.endswith('Dir'):
                        option_patterns['directory'].append((options_file, i, opt_name))
                    elif opt_name.endswith('Port'):
                        option_patterns['port'].append((options_file, i, opt_name))

        # Report inconsistent patterns (e.g., dataDir vs stateDir vs configDir)
        if 'directory' in option_patterns and len(option_patterns['directory']) > 3:
            dir_names = {name for _, _, name in option_patterns['directory']}
            if len(dir_names) > 2:  # More than 2 different patterns
                self.report.add_issue(
                    "NAMING_DRIFT", "SUGGESTION",
                    "multiple files",
                    f"Inconsistent directory option naming: {', '.join(sorted(dir_names))} (consider standardizing)"
                )

    def check_sys_coupling(self):
        """
        Category 5: sys.nix coupling mistakes
        CHARTER Section 6 (Lane Purity, sys.nix Architecture)
        """
        for sys_file in self.search_path.rglob("sys.nix"):
            content = sys_file.read_text()
            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                # Check for references to hwc.home options (wrong lane)
                if re.search(r'config\.hwc\.home\.[a-zA-Z]', line):
                    self.report.add_issue(
                        "SYS_COUPLING", "HIGH",
                        f"{sys_file.relative_to(self.search_path)}:{i}",
                        "sys.nix references config.hwc.home.* (system evaluates before HM) (CHARTER §6)"
                    )

            # Check if sys.nix has conditional logic but no hwc.system.* options
            has_conditional = 'lib.mkIf' in content or 'lib.mkMerge' in content
            has_system_options = 'options.hwc.system.' in content

            if has_conditional and not has_system_options:
                self.report.add_issue(
                    "SYS_COUPLING", "MED",
                    str(sys_file.relative_to(self.search_path)),
                    "sys.nix has conditional logic but no hwc.system.* options (should define system-lane API) (CHARTER §6)"
                )

    def check_profile_structure(self):
        """
        Check profile structure for BASE/OPTIONAL sections
        CHARTER Section 2 (Profile Pattern)
        """
        profiles_path = self.search_path / "profiles"
        if not profiles_path.exists():
            return

        for profile_file in profiles_path.glob("*.nix"):
            content = profile_file.read_text()

            # Check for section markers
            has_base = "# BASE" in content or "#==========================================================================\n  # BASE" in content
            has_optional = "# OPTIONAL" in content or "OPTIONAL FEATURES" in content

            if not has_base and not has_optional:
                self.report.add_issue(
                    "PROFILE_STRUCTURE", "MED",
                    str(profile_file.relative_to(self.search_path)),
                    "Profile missing BASE/OPTIONAL FEATURES sections (CHARTER §2)"
                )


def main():
    search_path = sys.argv[1] if len(sys.argv) > 1 else "."

    analyzer = DriftAnalyzer(search_path)
    return analyzer.analyze()


if __name__ == "__main__":
    sys.exit(main())
