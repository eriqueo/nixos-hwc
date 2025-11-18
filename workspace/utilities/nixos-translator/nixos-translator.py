#!/usr/bin/env python3
"""
NixOS Translator - Convert NixOS configurations to distro-agnostic format

This tool scans a NixOS configuration repository and extracts:
- Enabled services
- Package lists
- Container definitions
- System configurations

It generates a Universal Intermediate Representation (IR) that can be
transformed into distro-specific configurations (Arch, Ubuntu, Fedora, etc.)
"""

import argparse
import os
import sys
from pathlib import Path
import yaml

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scanners.service_scanner import ServiceScanner
from scanners.package_scanner import PackageScanner
from scanners.container_scanner import ContainerScanner
from generators.universal_ir import UniversalIRGenerator
from generators.arch_backend import ArchBackend


class NixOSTranslator:
    def __init__(self, source_path, output_path, verbose=False):
        self.source_path = Path(source_path)
        self.output_path = Path(output_path)
        self.verbose = verbose

        if not self.source_path.exists():
            raise ValueError(f"Source path does not exist: {source_path}")

    def log(self, message):
        if self.verbose:
            print(f"[nixos-translator] {message}")

    def scan(self):
        """Scan the NixOS configuration and extract all information"""
        self.log("Starting scan of NixOS configuration...")

        # Initialize scanners
        service_scanner = ServiceScanner(self.source_path, verbose=self.verbose)
        package_scanner = PackageScanner(self.source_path, verbose=self.verbose)
        container_scanner = ContainerScanner(self.source_path, verbose=self.verbose)

        # Scan for services
        self.log("Scanning for enabled services...")
        services = service_scanner.scan()

        # Scan for packages
        self.log("Scanning for packages...")
        packages = package_scanner.scan()

        # Scan for containers
        self.log("Scanning for containers...")
        containers = container_scanner.scan()

        return {
            'services': services,
            'packages': packages,
            'containers': containers
        }

    def generate_universal_ir(self, scan_data):
        """Generate Universal Intermediate Representation"""
        self.log("Generating Universal IR...")

        generator = UniversalIRGenerator(self.output_path, verbose=self.verbose)
        universal_path = self.output_path / 'universal-hwc'

        generator.generate(scan_data, universal_path)

        return universal_path

    def generate_arch_configs(self, universal_path):
        """Generate Arch-specific configurations"""
        self.log("Generating Arch configurations...")

        backend = ArchBackend(verbose=self.verbose)
        arch_path = self.output_path / 'arch-hwc'

        backend.generate(universal_path, arch_path)

        return arch_path

    def export(self):
        """Export NixOS config to universal format"""
        self.log(f"Exporting NixOS config from: {self.source_path}")

        # Scan the configuration
        scan_data = self.scan()

        # Generate universal IR
        universal_path = self.generate_universal_ir(scan_data)

        self.log(f"✅ Universal IR generated at: {universal_path}")

        return universal_path

    def generate(self, target_distro):
        """Generate distro-specific configurations"""
        universal_path = self.output_path / 'universal-hwc'

        if not universal_path.exists():
            raise ValueError(f"Universal IR not found at {universal_path}. Run 'export' first.")

        self.log(f"Generating configs for: {target_distro}")

        if target_distro == 'arch':
            output_path = self.generate_arch_configs(universal_path)
            self.log(f"✅ Arch configs generated at: {output_path}")
        else:
            raise ValueError(f"Unsupported target distro: {target_distro}")

        return output_path


def main():
    parser = argparse.ArgumentParser(
        description='NixOS Translator - Convert NixOS configs to distro-agnostic format'
    )

    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # Export command
    export_parser = subparsers.add_parser('export', help='Export NixOS config to universal format')
    export_parser.add_argument('--source', required=True, help='Path to NixOS config directory')
    export_parser.add_argument('--output', required=True, help='Output directory')
    export_parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    # Generate command
    generate_parser = subparsers.add_parser('generate', help='Generate distro-specific configs')
    generate_parser.add_argument('--source', required=True, help='Path to universal-hwc directory')
    generate_parser.add_argument('--target', required=True, choices=['arch', 'ubuntu', 'fedora'],
                                 help='Target distribution')
    generate_parser.add_argument('--output', required=True, help='Output directory')
    generate_parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    try:
        if args.command == 'export':
            translator = NixOSTranslator(args.source, args.output, verbose=args.verbose)
            translator.export()

        elif args.command == 'generate':
            # For generate, the source is actually the output from export
            output_dir = Path(args.output)
            translator = NixOSTranslator(args.source, output_dir, verbose=args.verbose)
            translator.generate(args.target)

        return 0

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
