"""
Package Scanner - Extracts package lists from NixOS configuration

Scans .nix files for package references in:
- environment.systemPackages
- home.packages
- Package lists in modules
"""

import re
from pathlib import Path
from typing import Dict, List, Set


class PackageScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.system_packages = set()
        self.home_packages = set()
        self.package_sources = {}  # Track where each package was found

    def log(self, message):
        if self.verbose:
            print(f"  [package-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for all package references"""
        self.log("Scanning for package lists...")

        # Scan domains (where packages are actually defined)
        self._scan_directory(self.source_path / 'domains')

        # Scan profiles (may have additional packages)
        self._scan_directory(self.source_path / 'profiles')

        self.log(f"Found {len(self.system_packages)} system packages")
        self.log(f"Found {len(self.home_packages)} home packages")

        return {
            'system': sorted(list(self.system_packages)),
            'home': sorted(list(self.home_packages)),
            'sources': self.package_sources
        }

    def _scan_directory(self, directory: Path):
        """Recursively scan directory for .nix files"""
        if not directory.exists():
            return

        for nix_file in directory.rglob('*.nix'):
            self._scan_file(nix_file)

    def _scan_file(self, file_path: Path):
        """Scan a single .nix file for package references"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Remove comments
            content = self._remove_comments(content)

            # Find package lists
            self._find_system_packages(content, file_path)
            self._find_home_packages(content, file_path)

        except Exception as e:
            self.log(f"Error scanning {file_path}: {e}")

    def _remove_comments(self, content: str) -> str:
        """Remove Nix comments from content"""
        content = re.sub(r'#.*$', '', content, flags=re.MULTILINE)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        return content

    def _find_system_packages(self, content: str, source_file: Path):
        """Find packages in environment.systemPackages"""
        # Look for systemPackages assignments
        patterns = [
            r'environment\.systemPackages\s*=\s*(?:with pkgs;\s*)?\[(.*?)\]',
            r'systemPackages\s*=\s*(?:with pkgs;\s*)?\[(.*?)\]',
        ]

        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL):
                packages_text = match.group(1)
                packages = self._extract_packages(packages_text)

                for pkg in packages:
                    self.system_packages.add(pkg)
                    self._track_source(pkg, 'system', source_file)

    def _find_home_packages(self, content: str, source_file: Path):
        """Find packages in home.packages"""
        patterns = [
            r'home\.packages\s*=\s*(?:with pkgs;\s*)?\[(.*?)\]',
        ]

        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL):
                packages_text = match.group(1)
                packages = self._extract_packages(packages_text)

                for pkg in packages:
                    self.home_packages.add(pkg)
                    self._track_source(pkg, 'home', source_file)

    def _extract_packages(self, packages_text: str) -> List[str]:
        """Extract individual package names from a package list"""
        packages = []

        # Split by whitespace and newlines
        tokens = re.split(r'\s+', packages_text.strip())

        for token in tokens:
            # Clean up the token
            token = token.strip()

            # Skip empty tokens
            if not token:
                continue

            # Skip comments and special characters
            if token.startswith('#') or token in ['', ']', '[', 'with', 'pkgs;']:
                continue

            # Handle pkgs.packageName
            if token.startswith('pkgs.'):
                token = token[5:]  # Remove 'pkgs.' prefix

            # Handle (lib.xxx ...)
            if token.startswith('(') or token.startswith('lib.'):
                continue

            # Remove trailing characters
            token = token.rstrip(',;')

            # Skip if still empty or contains invalid characters
            if token and re.match(r'^[a-zA-Z0-9_-]+$', token):
                packages.append(token)

        return packages

    def _track_source(self, package: str, package_type: str, source_file: Path):
        """Track where a package was found"""
        if package not in self.package_sources:
            self.package_sources[package] = {
                'type': package_type,
                'files': []
            }

        relative_path = str(source_file.relative_to(self.source_path))
        if relative_path not in self.package_sources[package]['files']:
            self.package_sources[package]['files'].append(relative_path)
