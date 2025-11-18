"""
Service Scanner - Extracts enabled services from NixOS configuration

Scans .nix files for service enable patterns like:
- hwc.server.jellyfin.enable = true
- services.jellyfin.enable = true
- hwc.home.apps.firefox.enable = true
"""

import re
from pathlib import Path
from typing import Dict, List, Set


class ServiceScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.services = {}

    def log(self, message):
        if self.verbose:
            print(f"  [service-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for all enabled services"""
        # Scan profiles first (these are the high-level feature toggles)
        self.log("Scanning profiles...")
        self._scan_directory(self.source_path / 'profiles')

        # Scan machine configs (these override profiles)
        self.log("Scanning machine configs...")
        self._scan_directory(self.source_path / 'machines')

        # Categorize services
        categorized = self._categorize_services()

        self.log(f"Found {len(self.services)} service definitions")
        return categorized

    def _scan_directory(self, directory: Path):
        """Recursively scan directory for .nix files"""
        if not directory.exists():
            return

        for nix_file in directory.rglob('*.nix'):
            self._scan_file(nix_file)

    def _scan_file(self, file_path: Path):
        """Scan a single .nix file for service definitions"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Remove comments to avoid false positives
            content = self._remove_comments(content)

            # Find all enable statements
            self._find_enable_statements(content, file_path)

        except Exception as e:
            self.log(f"Error scanning {file_path}: {e}")

    def _remove_comments(self, content: str) -> str:
        """Remove Nix comments from content"""
        # Remove single-line comments
        content = re.sub(r'#.*$', '', content, flags=re.MULTILINE)
        # Remove multi-line comments
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        return content

    def _find_enable_statements(self, content: str, source_file: Path):
        """Find all .enable = true statements"""
        # Pattern matches: hwc.domain.service.enable = true/lib.mkDefault true
        patterns = [
            # Direct enable
            r'(hwc\.[a-zA-Z0-9_.]+?)\.enable\s*=\s*true',
            # With mkDefault or mkForce
            r'(hwc\.[a-zA-Z0-9_.]+?)\.enable\s*=\s*lib\.mk(?:Default|Force)\s+true',
            # Standard NixOS services
            r'(services\.[a-zA-Z0-9_.]+?)\.enable\s*=\s*true',
            # Home-manager programs
            r'(programs\.[a-zA-Z0-9_.]+?)\.enable\s*=\s*true',
        ]

        for pattern in patterns:
            for match in re.finditer(pattern, content):
                service_path = match.group(1)
                self._add_service(service_path, source_file)

    def _add_service(self, service_path: str, source_file: Path):
        """Add a service to the registry"""
        if service_path not in self.services:
            self.services[service_path] = {
                'path': service_path,
                'enabled_in': str(source_file.relative_to(self.source_path)),
                'category': self._infer_category(service_path),
                'type': self._infer_type(service_path)
            }

    def _infer_category(self, service_path: str) -> str:
        """Infer the category of a service from its path"""
        parts = service_path.split('.')

        # hwc.server.* → server workloads
        if 'server' in parts:
            return 'server'

        # hwc.home.* or programs.* → user applications
        if 'home' in parts or service_path.startswith('programs.'):
            return 'home'

        # hwc.system.* or services.* → system services
        if 'system' in parts or service_path.startswith('services.'):
            return 'system'

        # hwc.infrastructure.* → infrastructure
        if 'infrastructure' in parts:
            return 'infrastructure'

        # hwc.services.containers.* → containerized services
        if 'containers' in parts:
            return 'container'

        return 'unknown'

    def _infer_type(self, service_path: str) -> str:
        """Infer if service is native or containerized"""
        if 'containers' in service_path:
            return 'container'

        # Known native services
        native_services = ['jellyfin', 'immich', 'navidrome', 'frigate', 'ollama', 'couchdb']
        for svc in native_services:
            if svc in service_path:
                return 'native'

        return 'unknown'

    def _categorize_services(self) -> Dict:
        """Organize services by category"""
        categorized = {
            'server': [],
            'home': [],
            'system': [],
            'infrastructure': [],
            'containers': [],
            'unknown': []
        }

        for service_path, service_data in self.services.items():
            category = service_data['category']
            service_type = service_data['type']

            # Container services go in special category
            if service_type == 'container':
                categorized['containers'].append(service_data)
            elif category in categorized:
                categorized[category].append(service_data)
            else:
                categorized['unknown'].append(service_data)

        # Remove empty categories
        return {k: v for k, v in categorized.items() if v}
