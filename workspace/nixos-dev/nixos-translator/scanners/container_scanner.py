"""
Container Scanner - Extracts container definitions from NixOS configuration

Scans for:
- virtualisation.oci-containers.containers definitions
- Docker/Podman container configurations
"""

import re
from pathlib import Path
from typing import Dict, List


class ContainerScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.containers = []

    def log(self, message):
        if self.verbose:
            print(f"  [container-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for all container definitions"""
        self.log("Scanning for containers...")

        # Scan domains/server for container definitions
        server_domain = self.source_path / 'domains' / 'server'
        if server_domain.exists():
            self._scan_directory(server_domain)

        self.log(f"Found {len(self.containers)} container definitions")

        return {
            'containers': self.containers,
            'total': len(self.containers)
        }

    def _scan_directory(self, directory: Path):
        """Recursively scan directory for .nix files with container definitions"""
        if not directory.exists():
            return

        for nix_file in directory.rglob('*.nix'):
            self._scan_file(nix_file)

    def _scan_file(self, file_path: Path):
        """Scan a single .nix file for container definitions"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Look for container definitions
            self._find_containers(content, file_path)

        except Exception as e:
            self.log(f"Error scanning {file_path}: {e}")

    def _find_containers(self, content: str, source_file: Path):
        """Find container definitions in the file"""
        # Pattern to match container name and basic info
        # Looking for: virtualisation.oci-containers.containers.NAME
        container_pattern = r'virtualisation\.oci-containers\.containers\.(\w+)\s*='

        for match in re.finditer(container_pattern, content):
            container_name = match.group(1)

            # Try to extract more details about this container
            container_info = self._extract_container_info(content, container_name, source_file)

            if container_info:
                self.containers.append(container_info)

    def _extract_container_info(self, content: str, name: str, source_file: Path) -> Dict:
        """Extract detailed information about a container"""
        # This is a simplified extractor - in practice, you'd need to parse Nix AST
        # For now, we'll just capture the container exists and where it's defined

        # Try to find the image
        image_pattern = rf'containers\.{name}.*?image\s*=\s*"([^"]+)"'
        image_match = re.search(image_pattern, content, re.DOTALL)
        image = image_match.group(1) if image_match else 'unknown'

        # Try to find ports (simplified)
        ports = []
        port_pattern = rf'containers\.{name}.*?ports\s*=\s*\[(.*?)\]'
        port_match = re.search(port_pattern, content, re.DOTALL)
        if port_match:
            port_text = port_match.group(1)
            # Extract port strings like "8080:8080"
            port_strings = re.findall(r'"(\d+:\d+)"', port_text)
            ports = port_strings

        return {
            'name': name,
            'image': image,
            'ports': ports,
            'source_file': str(source_file.relative_to(self.source_path)),
            'type': 'oci-container'
        }
