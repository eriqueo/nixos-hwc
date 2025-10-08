#!/usr/bin/env python3
"""
NixOS Configuration Extractor - Analyzes undeployed configurations safely
Extracts what the configuration WOULD create without deploying it.

Usage:
    ./config-extractor.py /etc/nixos > current-config-intent.json
    ./config-extractor.py /home/eric/.nixos > new-config-intent.json
    diff <(jq -S . current-config-intent.json) <(jq -S . new-config-intent.json)
"""

import json
import subprocess
import re
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
import tempfile

class ConfigExtractor:
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.output = {
            "metadata": {},
            "containers": {},
            "systemd_services": {},
            "environment_variables": {},
            "firewall": {},
            "mounts": {},
            "secrets": {},
            "errors": []
        }
    
    def run_cmd(self, cmd: List[str], cwd: Optional[str] = None) -> Optional[str]:
        """Run command and return output, or None if failed"""
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, 
                cwd=cwd or str(self.config_path), timeout=60
            )
            if result.returncode == 0:
                return result.stdout.strip()
            else:
                self.output["errors"].append({
                    "command": " ".join(cmd),
                    "error": result.stderr.strip()
                })
                return None
        except Exception as e:
            self.output["errors"].append({
                "command": " ".join(cmd),
                "error": str(e)
            })
            return None
    
    def extract_metadata(self):
        """Extract basic config metadata"""
        flake_nix = self.config_path / "flake.nix"
        
        self.output["metadata"] = {
            "config_path": str(self.config_path),
            "has_flake": flake_nix.exists(),
            "timestamp": subprocess.run(["date", "-Iseconds"], capture_output=True, text=True).stdout.strip()
        }
        
        if flake_nix.exists():
            # Extract nixosConfigurations from flake.nix
            try:
                with open(flake_nix) as f:
                    content = f.read()
                    # Simple regex to find nixosConfigurations
                    configs = re.findall(r'nixosConfigurations\.(\w+)', content)
                    self.output["metadata"]["flake_configs"] = list(set(configs))
            except:
                pass
    
    def evaluate_config_safely(self, host: str = "hwc-server") -> Optional[Dict]:
        """Use nix eval to safely extract configuration without building"""
        
        # Try different evaluation approaches
        eval_commands = [
            # Evaluate containers configuration
            ["nix", "eval", "--json", f".#nixosConfigurations.{host}.config.virtualisation.oci-containers.containers", "--impure"],
            # Fallback for different flake structure
            ["nix", "eval", "--json", f".#nixosConfigurations.{host}.config.services", "--impure"],
        ]
        
        config_data = {}
        
        for cmd in eval_commands:
            result = self.run_cmd(cmd)
            if result:
                try:
                    data = json.loads(result)
                    if "oci-containers" in cmd[-2]:
                        config_data["containers"] = data
                    elif "services" in cmd[-2]:
                        config_data["services"] = data
                    break
                except json.JSONDecodeError:
                    continue
        
        return config_data if config_data else None
    
    def extract_containers_from_files(self):
        """Extract container configs by parsing Nix files directly"""
        containers = {}
        
        # Find container-related files
        container_files = []
        for pattern in ["**/containers/**/*.nix", "**/media-containers.nix", "**/*container*.nix"]:
            container_files.extend(self.config_path.glob(pattern))
        
        for file_path in container_files:
            try:
                with open(file_path) as f:
                    content = f.read()
                    
                    # Extract container definitions using regex
                    # Look for virtualisation.oci-containers.containers.NAME patterns
                    container_matches = re.finditer(
                        r'virtualisation\.oci-containers\.containers\.(\w+)\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}',
                        content, re.MULTILINE | re.DOTALL
                    )
                    
                    for match in container_matches:
                        name = match.group(1)
                        definition = match.group(2)
                        
                        container_info = {
                            "file": str(file_path.relative_to(self.config_path)),
                            "name": name,
                            "raw_definition": definition.strip()
                        }
                        
                        # Extract key properties with regex
                        image_match = re.search(r'image\s*=\s*["\']([^"\']+)["\']', definition)
                        if image_match:
                            container_info["image"] = image_match.group(1)
                        
                        # Extract volumes array
                        volumes_match = re.search(r'volumes\s*=\s*\[([^\]]+)\]', definition, re.DOTALL)
                        if volumes_match:
                            volumes_text = volumes_match.group(1)
                            # Extract quoted strings
                            volume_matches = re.findall(r'["\']([^"\']+)["\']', volumes_text)
                            container_info["volumes"] = volume_matches
                        
                        # Extract ports array
                        ports_match = re.search(r'ports\s*=\s*\[([^\]]+)\]', definition, re.DOTALL)
                        if ports_match:
                            ports_text = ports_match.group(1)
                            port_matches = re.findall(r'["\']([^"\']+)["\']', ports_text)
                            container_info["ports"] = port_matches
                        
                        # Extract environment
                        env_match = re.search(r'environment\s*=\s*\{([^}]+)\}', definition, re.DOTALL)
                        if env_match:
                            env_text = env_match.group(1)
                            container_info["environment_raw"] = env_text.strip()
                        
                        containers[name] = container_info
                        
            except Exception as e:
                self.output["errors"].append({
                    "file": str(file_path),
                    "error": f"Failed to parse: {e}"
                })
        
        self.output["containers"] = containers
    
    def extract_systemd_services(self):
        """Extract systemd service definitions from Nix files"""
        services = {}
        
        # Find all nix files that might define services
        nix_files = list(self.config_path.glob("**/*.nix"))
        
        for file_path in nix_files:
            try:
                with open(file_path) as f:
                    content = f.read()
                    
                    # Look for systemd.services.NAME patterns
                    service_matches = re.finditer(
                        r'systemd\.services\.([a-zA-Z0-9_-]+)\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}',
                        content, re.MULTILINE | re.DOTALL
                    )
                    
                    for match in service_matches:
                        name = match.group(1)
                        definition = match.group(2)
                        
                        services[name] = {
                            "file": str(file_path.relative_to(self.config_path)),
                            "definition": definition.strip()
                        }
                        
            except Exception as e:
                self.output["errors"].append({
                    "file": str(file_path),
                    "error": f"Failed to parse services: {e}"
                })
        
        self.output["systemd_services"] = services
    
    def extract_environment_variables(self):
        """Extract environment.variables definitions"""
        env_vars = {}
        
        nix_files = list(self.config_path.glob("**/*.nix"))
        
        for file_path in nix_files:
            try:
                with open(file_path) as f:
                    content = f.read()
                    
                    # Look for environment.variables patterns
                    env_matches = re.finditer(
                        r'environment\.variables\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}',
                        content, re.MULTILINE | re.DOTALL
                    )
                    
                    for match in env_matches:
                        definition = match.group(1)
                        
                        # Extract individual variables
                        var_matches = re.findall(r'(\w+)\s*=\s*["\']([^"\']*)["\']', definition)
                        for var_name, var_value in var_matches:
                            env_vars[var_name] = {
                                "value": var_value,
                                "file": str(file_path.relative_to(self.config_path))
                            }
                        
            except Exception as e:
                self.output["errors"].append({
                    "file": str(file_path),
                    "error": f"Failed to parse environment: {e}"
                })
        
        self.output["environment_variables"] = env_vars
    
    def extract_secrets(self):
        """Extract SOPS/age secret definitions"""
        secrets = {}
        
        # Look for sops.secrets definitions
        nix_files = list(self.config_path.glob("**/*.nix"))
        
        for file_path in nix_files:
            try:
                with open(file_path) as f:
                    content = f.read()
                    
                    # Look for sops.secrets patterns
                    secret_matches = re.finditer(
                        r'sops\.secrets\.([a-zA-Z0-9_-]+)\s*=\s*\{([^}]+)\}',
                        content, re.MULTILINE | re.DOTALL
                    )
                    
                    for match in secret_matches:
                        name = match.group(1)
                        definition = match.group(2)
                        
                        secrets[name] = {
                            "file": str(file_path.relative_to(self.config_path)),
                            "definition": definition.strip()
                        }
                        
            except Exception as e:
                self.output["errors"].append({
                    "file": str(file_path),
                    "error": f"Failed to parse secrets: {e}"
                })
        
        # Also check for secrets files
        secrets_dir = self.config_path / "secrets"
        if secrets_dir.exists():
            secret_files = list(secrets_dir.glob("*.yaml")) + list(secrets_dir.glob("*.env"))
            secrets["_files"] = [str(f.relative_to(self.config_path)) for f in secret_files]
        
        self.output["secrets"] = secrets
    
    def analyze_critical_paths(self):
        """Analyze critical container volume mounts and dependencies"""
        critical_analysis = {
            "sabnzbd_volumes": [],
            "events_mounts": [],
            "script_mounts": [],
            "vpn_dependencies": [],
            "media_orchestrator": False
        }
        
        # Check SABnzbd specifically
        if "sabnzbd" in self.output["containers"]:
            sabnzbd = self.output["containers"]["sabnzbd"]
            if "volumes" in sabnzbd:
                critical_analysis["sabnzbd_volumes"] = sabnzbd["volumes"]
                
                # Check for critical mounts
                for volume in sabnzbd["volumes"]:
                    if "events" in volume:
                        critical_analysis["events_mounts"].append(volume)
                    if "scripts" in volume:
                        critical_analysis["script_mounts"].append(volume)
        
        # Check for media-orchestrator service
        orchestrator_services = [name for name in self.output["systemd_services"] 
                               if "orchestrator" in name or "media-orchestrator" in name]
        critical_analysis["media_orchestrator"] = len(orchestrator_services) > 0
        
        # Check for VPN dependencies
        for container_name, container in self.output["containers"].items():
            if "gluetun" in container.get("raw_definition", ""):
                critical_analysis["vpn_dependencies"].append(container_name)
        
        self.output["critical_analysis"] = critical_analysis
    
    def extract_all(self):
        """Run all extraction methods"""
        print("Extracting configuration metadata...", file=sys.stderr)
        self.extract_metadata()
        
        print("Extracting container definitions...", file=sys.stderr)
        self.extract_containers_from_files()
        
        print("Extracting systemd services...", file=sys.stderr)
        self.extract_systemd_services()
        
        print("Extracting environment variables...", file=sys.stderr)
        self.extract_environment_variables()
        
        print("Extracting secrets configuration...", file=sys.stderr)
        self.extract_secrets()
        
        print("Analyzing critical paths...", file=sys.stderr)
        self.analyze_critical_paths()
        
        return self.output

def main():
    if len(sys.argv) < 2:
        print("Usage: config-extractor.py <config-path>", file=sys.stderr)
        print("Example: config-extractor.py /etc/nixos", file=sys.stderr)
        sys.exit(1)
    
    config_path = sys.argv[1]
    
    if not os.path.exists(config_path):
        print(f"Error: Config path {config_path} does not exist", file=sys.stderr)
        sys.exit(1)
    
    extractor = ConfigExtractor(config_path)
    result = extractor.extract_all()
    
    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()