#!/usr/bin/env python3
"""
Nix Configuration Evaluator

Uses `nix eval --json` to accurately extract container configurations
instead of fragile regex parsing. This fixes:
- Missing volumes and environment variables
- Conditional logic (lib.optionals, lib.mkIf)
- Dynamic path references (${paths.hot})
- Port calculations (toString cfg.webPort)

Run this ON the NixOS machine to get accurate evaluated configs.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List


class NixEvaluator:
    def __init__(self, flake_path: str, machine: str, verbose: bool = False):
        self.flake_path = Path(flake_path)
        self.machine = machine
        self.verbose = verbose

    def log(self, message):
        if self.verbose:
            print(f"[nix-eval] {message}", file=sys.stderr)

    def eval_containers(self) -> Dict:
        """Evaluate container configurations using nix eval"""
        self.log(f"Evaluating containers for machine: {self.machine}")

        # Nix expression to evaluate
        expr = f".#nixosConfigurations.{self.machine}.config.virtualisation.oci-containers.containers"

        try:
            result = subprocess.run(
                ["nix", "eval", "--json", expr],
                cwd=self.flake_path,
                capture_output=True,
                text=True,
                check=True
            )

            containers = json.loads(result.stdout)
            self.log(f"Successfully evaluated {len(containers)} containers")

            return self._normalize_containers(containers)

        except subprocess.CalledProcessError as e:
            self.log(f"Error evaluating Nix config: {e.stderr}")
            raise
        except json.JSONDecodeError as e:
            self.log(f"Error parsing Nix output: {e}")
            raise

    def eval_system_config(self) -> Dict:
        """Evaluate system configuration (users, networking, etc.)"""
        self.log("Evaluating system configuration...")

        configs = {}

        # Users
        try:
            result = subprocess.run(
                ["nix", "eval", "--json",
                 f".#nixosConfigurations.{self.machine}.config.users.users"],
                cwd=self.flake_path,
                capture_output=True,
                text=True,
                check=True
            )
            configs['users'] = json.loads(result.stdout)
        except Exception as e:
            self.log(f"Could not evaluate users: {e}")
            configs['users'] = {}

        # Firewall
        try:
            result = subprocess.run(
                ["nix", "eval", "--json",
                 f".#nixosConfigurations.{self.machine}.config.networking.firewall"],
                cwd=self.flake_path,
                capture_output=True,
                text=True,
                check=True
            )
            configs['firewall'] = json.loads(result.stdout)
        except Exception as e:
            self.log(f"Could not evaluate firewall: {e}")
            configs['firewall'] = {}

        # Paths
        try:
            result = subprocess.run(
                ["nix", "eval", "--json",
                 f".#nixosConfigurations.{self.machine}.config.hwc.paths"],
                cwd=self.flake_path,
                capture_output=True,
                text=True,
                check=True
            )
            configs['paths'] = json.loads(result.stdout)
        except Exception as e:
            self.log(f"Could not evaluate paths: {e}")
            configs['paths'] = {}

        return configs

    def eval_secrets(self) -> Dict:
        """Evaluate secrets configuration"""
        self.log("Evaluating secrets...")

        try:
            result = subprocess.run(
                ["nix", "eval", "--json",
                 f".#nixosConfigurations.{self.machine}.config.age.secrets"],
                cwd=self.flake_path,
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except Exception as e:
            self.log(f"Could not evaluate secrets: {e}")
            return {}

    def _normalize_containers(self, containers: Dict) -> Dict:
        """Normalize evaluated container configs into a standard format"""
        normalized = {}

        for name, config in containers.items():
            normalized[name] = {
                'name': name,
                'image': config.get('image', 'unknown'),
                'ports': self._normalize_ports(config.get('ports', [])),
                'volumes': self._normalize_volumes(config.get('volumes', [])),
                'environment': config.get('environment', {}),
                'extra_options': config.get('extraOptions', []),
                'depends_on': config.get('dependsOn', []),
                'auto_start': config.get('autoStart', True),
                'environment_files': config.get('environmentFiles', [])
            }

        return normalized

    def _normalize_ports(self, ports: List) -> List[Dict]:
        """Normalize port mappings"""
        normalized = []

        for port in ports:
            if isinstance(port, str):
                # Format: "host:container" or "host:container/proto"
                parts = port.split('/')
                port_mapping = parts[0]
                proto = parts[1] if len(parts) > 1 else 'tcp'

                if ':' in port_mapping:
                    host, container = port_mapping.split(':')
                    normalized.append({
                        'host': host.replace('0.0.0.0:', ''),
                        'container': container,
                        'proto': proto
                    })

        return normalized

    def _normalize_volumes(self, volumes: List) -> List[Dict]:
        """Normalize volume mounts"""
        normalized = []

        for vol in volumes:
            if isinstance(vol, str):
                # Format: "host:container" or "host:container:mode"
                parts = vol.split(':')

                if len(parts) >= 2:
                    normalized.append({
                        'host': parts[0],
                        'container': parts[1],
                        'mode': parts[2] if len(parts) > 2 else 'rw'
                    })

        return normalized


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Evaluate NixOS configuration using nix eval'
    )
    parser.add_argument('--flake', required=True, help='Path to NixOS flake directory')
    parser.add_argument('--machine', required=True, help='Machine name (laptop/server)')
    parser.add_argument('--output', required=True, help='Output JSON file')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    evaluator = NixEvaluator(args.flake, args.machine, verbose=args.verbose)

    # Evaluate all configurations
    output = {
        'machine': args.machine,
        'containers': evaluator.eval_containers(),
        'system': evaluator.eval_system_config(),
        'secrets': evaluator.eval_secrets()
    }

    # Write output
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"Evaluated configuration written to: {args.output}")


if __name__ == '__main__':
    main()
