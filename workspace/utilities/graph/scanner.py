"""
Scanner for NixOS module dependencies in the hwc repository.

Extracts module definitions and their dependencies by parsing:
- options.nix files for module names
- index.nix files for assertions and dependencies
- Comments for explicit dependency declarations
"""

import re
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field


@dataclass
class Module:
    """Represents a NixOS module in the hwc configuration."""
    name: str  # e.g., "hwc.server.jellyfin"
    domain: str  # e.g., "server", "infrastructure", "home"
    path: Path  # filesystem path to module directory
    kind: str  # "service" | "infrastructure" | "system" | "home" | "profile"

    # Dependencies
    requires: Set[str] = field(default_factory=set)  # Direct dependencies
    required_by: Set[str] = field(default_factory=set)  # Reverse dependencies

    # Optional metadata
    ports: List[int] = field(default_factory=list)
    description: str = ""

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        if isinstance(other, Module):
            return self.name == other.name
        return False


class ModuleScanner:
    """Scans the repository for modules and their dependencies."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.domains_path = repo_root / "domains"
        self.modules: Dict[str, Module] = {}

    def scan(self) -> Dict[str, Module]:
        """Scan the repository and return all discovered modules."""
        print("Scanning repository for modules...")

        # Scan all domains
        for domain_dir in self.domains_path.iterdir():
            if not domain_dir.is_dir() or domain_dir.name.startswith('.'):
                continue

            domain_name = domain_dir.name
            self._scan_domain(domain_name, domain_dir)

        # Build reverse dependencies
        self._build_reverse_deps()

        print(f"Found {len(self.modules)} modules")
        return self.modules

    def _scan_domain(self, domain_name: str, domain_path: Path):
        """Recursively scan a domain directory for modules."""
        # Look for options.nix files which indicate a module
        for options_file in domain_path.rglob("options.nix"):
            module_dir = options_file.parent

            # Skip if not in a proper module structure
            if not (module_dir / "index.nix").exists():
                continue

            # Extract module name from options.nix
            module_name = self._extract_module_name(options_file, domain_name)
            if not module_name:
                continue

            # Determine module kind
            kind = self._classify_module(domain_name, module_dir)

            # Create module entry
            module = Module(
                name=module_name,
                domain=domain_name,
                path=module_dir,
                kind=kind
            )

            # Extract dependencies from index.nix
            index_file = module_dir / "index.nix"
            if index_file.exists():
                deps = self._extract_dependencies(index_file, module_name)
                module.requires.update(deps)

            # Extract metadata
            module.description = self._extract_description(options_file)
            module.ports = self._extract_ports(options_file)

            self.modules[module_name] = module

    def _extract_module_name(self, options_file: Path, domain_name: str) -> Optional[str]:
        """
        Extract module name from options.nix.

        Looks for patterns like:
          options.hwc.server.jellyfin = { ... }
          options.hwc.infrastructure.hardware.gpu = { ... }
        """
        content = options_file.read_text()

        # Pattern: options.hwc.<domain>.<module...> = {
        pattern = r'options\.hwc\.([a-zA-Z0-9_.]+)\s*='
        matches = re.findall(pattern, content)

        if matches:
            # Take the most specific (longest) match
            longest = max(matches, key=len)
            return f"hwc.{longest}"

        return None

    def _extract_dependencies(self, index_file: Path, module_name: str) -> Set[str]:
        """
        Extract dependencies from index.nix.

        Looks for:
        1. Assertions: assertion = !cfg.enable || config.hwc.X.Y.enable
        2. Comments: # DEPENDENCIES: hwc.X.Y
        3. Config references: config.hwc.X.Y in conditional expressions
        """
        content = index_file.read_text()
        dependencies = set()

        # 1. Extract from comment headers
        comment_deps = self._extract_from_comments(content)
        dependencies.update(comment_deps)

        # 2. Extract from assertions
        assertion_deps = self._extract_from_assertions(content, module_name)
        dependencies.update(assertion_deps)

        # 3. Extract from config references (less reliable, so mark as secondary)
        # For now, we'll rely on assertions and comments which are more explicit

        return dependencies

    def _extract_from_comments(self, content: str) -> Set[str]:
        """Extract dependencies from comment headers like # DEPENDENCIES:"""
        dependencies = set()

        # Look for comment blocks with DEPENDENCIES
        lines = content.split('\n')
        in_deps_section = False

        for line in lines:
            stripped = line.strip()

            # Start of dependencies section
            if 'DEPENDENCIES:' in stripped.upper():
                in_deps_section = True
                continue

            # In dependencies section
            if in_deps_section:
                # End if we hit another section or non-comment
                if not stripped.startswith('#') or stripped.startswith('##'):
                    in_deps_section = False
                    continue

                # Extract module names (hwc.X.Y.Z)
                matches = re.findall(r'hwc\.[a-zA-Z0-9_.]+', stripped)
                dependencies.update(matches)

        return dependencies

    def _extract_from_assertions(self, content: str, module_name: str) -> Set[str]:
        """
        Extract dependencies from assertion statements.

        Patterns:
          assertion = !cfg.enable || config.hwc.X.Y.enable
          assertion = config.hwc.X.Y.enable
          assertion = cfg.feature -> config.hwc.X.Y.enable
        """
        dependencies = set()

        # Find all assertion blocks
        assertion_pattern = r'assertion\s*=\s*([^;]+);'
        assertions = re.findall(assertion_pattern, content, re.MULTILINE | re.DOTALL)

        for assertion in assertions:
            # Extract hwc.X.Y references
            deps = re.findall(r'config\.hwc\.([a-zA-Z0-9_.]+)', assertion)

            for dep in deps:
                dep_name = f"hwc.{dep}"

                # Don't add self-references
                # (e.g., hwc.server.jellyfin shouldn't depend on hwc.server.jellyfin.enable)
                if not dep_name.startswith(module_name + "."):
                    dependencies.add(dep_name)

        return dependencies

    def _extract_description(self, options_file: Path) -> str:
        """Extract module description from options.nix."""
        content = options_file.read_text()

        # Look for mkEnableOption with description
        pattern = r'mkEnableOption\s+"([^"]+)"'
        match = re.search(pattern, content)

        if match:
            return match.group(1)

        return ""

    def _extract_ports(self, options_file: Path) -> List[int]:
        """Extract port numbers from options.nix."""
        content = options_file.read_text()
        ports = []

        # Look for port = <number> patterns
        pattern = r'port\s*=\s*(\d+)'
        matches = re.findall(pattern, content)

        for match in matches:
            ports.append(int(match))

        return ports

    def _classify_module(self, domain_name: str, module_path: Path) -> str:
        """Classify module type based on domain and path."""
        if domain_name == "infrastructure":
            return "infrastructure"
        elif domain_name == "system":
            return "system"
        elif domain_name == "home":
            return "home"
        elif domain_name == "server":
            # Check if it's a container or native service
            if "containers" in str(module_path):
                return "container"
            return "service"
        elif domain_name == "secrets":
            return "security"
        else:
            return "other"

    def _build_reverse_deps(self):
        """Build reverse dependency relationships."""
        for module_name, module in self.modules.items():
            for dep_name in module.requires:
                # Find the actual dependency module (may need to normalize names)
                dep_module = self._find_module_by_prefix(dep_name)
                if dep_module:
                    dep_module.required_by.add(module_name)

    def _find_module_by_prefix(self, prefix: str) -> Optional[Module]:
        """
        Find a module by name prefix.

        Handles cases where dependency is hwc.X.Y but module is hwc.X.Y.Z
        Returns the most specific match.
        """
        # Exact match first
        if prefix in self.modules:
            return self.modules[prefix]

        # Find modules that match the prefix
        matches = [
            (name, module)
            for name, module in self.modules.items()
            if name.startswith(prefix) or prefix.startswith(name)
        ]

        if matches:
            # Return the closest match (prefer exact prefix matches)
            exact_prefixes = [(n, m) for n, m in matches if n.startswith(prefix)]
            if exact_prefixes:
                # Return shortest (most general) match
                return min(exact_prefixes, key=lambda x: len(x[0]))[1]
            else:
                # Return module that the prefix extends
                parent_matches = [(n, m) for n, m in matches if prefix.startswith(n)]
                if parent_matches:
                    return max(parent_matches, key=lambda x: len(x[0]))[1]

        return None


def scan_repository(repo_root: Path) -> Dict[str, Module]:
    """Convenience function to scan repository for modules."""
    scanner = ModuleScanner(repo_root)
    return scanner.scan()
