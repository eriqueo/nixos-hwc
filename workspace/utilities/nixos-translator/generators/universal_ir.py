"""
Universal IR Generator - Creates distro-agnostic intermediate representation

Generates YAML files that describe the system in a universal format:
- services.yml: Service definitions
- packages.yml: Package lists
- containers.yml: Container configurations
- README.md: Documentation
"""

import yaml
from pathlib import Path
from typing import Dict
from datetime import datetime


class UniversalIRGenerator:
    def __init__(self, output_path: Path, verbose: bool = False):
        self.output_path = Path(output_path)
        self.verbose = verbose

    def log(self, message):
        if self.verbose:
            print(f"  [universal-ir] {message}")

    def generate(self, scan_data: Dict, universal_path: Path):
        """Generate all universal IR files"""
        # Create output directory
        universal_path.mkdir(parents=True, exist_ok=True)

        # Generate each component
        self._generate_services_yml(scan_data['services'], universal_path)
        self._generate_packages_yml(scan_data['packages'], universal_path)
        self._generate_containers_yml(scan_data['containers'], universal_path)

        # Generate new comprehensive components
        if 'dotfiles' in scan_data:
            self._generate_dotfiles_yml(scan_data['dotfiles'], universal_path)

        if 'system' in scan_data:
            self._generate_system_yml(scan_data['system'], universal_path)

        if 'secrets' in scan_data:
            self._generate_secrets_yml(scan_data['secrets'], universal_path)

        self._generate_readme(universal_path, scan_data)

        self.log(f"Generated universal IR at: {universal_path}")

    def _generate_services_yml(self, services: Dict, output_path: Path):
        """Generate services.yml"""
        self.log("Generating services.yml...")

        # Organize services by category with metadata
        services_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS configuration',
                'format_version': '1.0'
            },
            'services': {}
        }

        for category, service_list in services.items():
            if not service_list:
                continue

            services_data['services'][category] = []

            for service in service_list:
                # Create a clean service definition
                service_def = {
                    'name': self._extract_service_name(service['path']),
                    'nixos_path': service['path'],
                    'enabled': True,
                    'type': service.get('type', 'unknown'),
                    'source_file': service.get('enabled_in', ''),
                }

                # Add additional metadata if we can infer it
                service_name = service_def['name']
                if service_name in self._get_known_services():
                    known_info = self._get_known_services()[service_name]
                    service_def.update(known_info)

                services_data['services'][category].append(service_def)

        # Write to file
        output_file = output_path / 'services.yml'
        with open(output_file, 'w') as f:
            yaml.dump(services_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")

    def _generate_packages_yml(self, packages: Dict, output_path: Path):
        """Generate packages.yml"""
        self.log("Generating packages.yml...")

        packages_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS configuration',
                'format_version': '1.0'
            },
            'packages': {
                'system': [],
                'home': []
            }
        }

        # Process system packages
        for pkg in packages.get('system', []):
            pkg_info = {
                'nixos_name': pkg,
                'category': self._categorize_package(pkg)
            }

            # Add known mappings if available
            if pkg in self._get_package_mappings():
                pkg_info['mappings'] = self._get_package_mappings()[pkg]

            packages_data['packages']['system'].append(pkg_info)

        # Process home packages
        for pkg in packages.get('home', []):
            pkg_info = {
                'nixos_name': pkg,
                'category': self._categorize_package(pkg)
            }

            if pkg in self._get_package_mappings():
                pkg_info['mappings'] = self._get_package_mappings()[pkg]

            packages_data['packages']['home'].append(pkg_info)

        # Write to file
        output_file = output_path / 'packages.yml'
        with open(output_file, 'w') as f:
            yaml.dump(packages_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")

    def _generate_containers_yml(self, containers: Dict, output_path: Path):
        """Generate containers.yml"""
        self.log("Generating containers.yml...")

        containers_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS configuration',
                'format_version': '1.0',
                'note': 'These can be directly translated to docker-compose.yml'
            },
            'containers': containers.get('containers', [])
        }

        # Write to file
        output_file = output_path / 'containers.yml'
        with open(output_file, 'w') as f:
            yaml.dump(containers_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")

    def _generate_readme(self, output_path: Path, scan_data: Dict):
        """Generate README.md explaining the universal IR"""
        self.log("Generating README.md...")

        total_services = sum(len(v) for v in scan_data['services'].values())
        total_system_packages = len(scan_data['packages'].get('system', []))
        total_home_packages = len(scan_data['packages'].get('home', []))
        total_containers = scan_data['containers'].get('total', 0)

        readme_content = f"""# Universal Hardware Configuration (Universal IR)

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This directory contains a **distro-agnostic** representation of your NixOS configuration.
The Universal Intermediate Representation (IR) can be transformed into configurations for
any Linux distribution (Arch, Ubuntu, Fedora, etc.).

## Contents

- **services.yml** - Service definitions ({total_services} services)
- **packages.yml** - Package lists ({total_system_packages} system, {total_home_packages} home)
- **containers.yml** - Container configurations ({total_containers} containers)

## Statistics

### Services by Category
"""

        for category, services in scan_data['services'].items():
            if services:
                readme_content += f"- **{category}**: {len(services)} services\n"

        readme_content += f"""
### Packages
- **System packages**: {total_system_packages}
- **Home packages**: {total_home_packages}

### Containers
- **Total containers**: {total_containers}

## Usage

### Generate Arch Linux Configuration

```bash
../nixos-translator.py generate \\
  --source . \\
  --target arch \\
  --output ~/arch-hwc \\
  --verbose
```

### Generate Ubuntu Configuration (future)

```bash
../nixos-translator.py generate \\
  --source . \\
  --target ubuntu \\
  --output ~/ubuntu-hwc \\
  --verbose
```

## Format Version

This IR uses format version 1.0. The format is designed to be:
- **Declarative**: Describes desired state, not imperative steps
- **Portable**: Works across any Linux distribution
- **Extensible**: Easy to add new backends for other distros
- **Human-readable**: YAML format for easy inspection and modification

## Next Steps

1. Review the generated files to ensure accuracy
2. Run the `generate` command for your target distribution
3. Follow the distro-specific installation guide in the generated directory
"""

        # Write to file
        output_file = output_path / 'README.md'
        with open(output_file, 'w') as f:
            f.write(readme_content)

        self.log(f"Created: {output_file}")

    def _extract_service_name(self, service_path: str) -> str:
        """Extract a clean service name from the NixOS path"""
        # hwc.server.jellyfin.enable → jellyfin
        # services.jellyfin.enable → jellyfin
        parts = service_path.split('.')

        # Filter out common prefixes
        filtered = [p for p in parts if p not in ['hwc', 'services', 'programs', 'enable', 'server', 'home', 'apps', 'system']]

        return filtered[-1] if filtered else service_path

    def _categorize_package(self, package: str) -> str:
        """Categorize a package by type"""
        # Development tools
        dev_tools = ['git', 'gcc', 'python', 'nodejs', 'rust', 'go', 'neovim', 'vim', 'tmux']
        if any(tool in package.lower() for tool in dev_tools):
            return 'development'

        # Desktop apps
        desktop_apps = ['firefox', 'chromium', 'obsidian', 'thunderbird', 'kitty', 'alacritty']
        if any(app in package.lower() for app in desktop_apps):
            return 'desktop'

        # System utilities
        system_utils = ['systemd', 'network', 'pulseaudio', 'pipewire', 'bluetooth']
        if any(util in package.lower() for util in system_utils):
            return 'system'

        return 'other'

    def _get_known_services(self) -> Dict:
        """Return known service definitions with metadata"""
        return {
            'jellyfin': {
                'port': 8096,
                'description': 'Media streaming server',
                'requires_gpu': True
            },
            'immich': {
                'port': 2283,
                'description': 'Photo management',
                'requires_gpu': True
            },
            'navidrome': {
                'port': 4533,
                'description': 'Music streaming server'
            },
            'frigate': {
                'port': 5000,
                'description': 'NVR camera surveillance',
                'requires_gpu': True
            },
            'ollama': {
                'port': 11434,
                'description': 'Local AI models',
                'requires_gpu': True
            },
            'couchdb': {
                'port': 5984,
                'description': 'Document database'
            },
            'sonarr': {
                'port': 8989,
                'description': 'TV show automation'
            },
            'radarr': {
                'port': 7878,
                'description': 'Movie automation'
            },
            'prowlarr': {
                'port': 9696,
                'description': 'Indexer manager'
            },
            'lidarr': {
                'port': 8686,
                'description': 'Music automation'
            },
            'qbittorrent': {
                'port': 8080,
                'description': 'Torrent client'
            }
        }

    def _get_package_mappings(self) -> Dict:
        """Return known package name mappings across distros"""
        return {
            'git': {'arch': 'git', 'ubuntu': 'git', 'fedora': 'git'},
            'neovim': {'arch': 'neovim', 'ubuntu': 'neovim', 'fedora': 'neovim'},
            'tmux': {'arch': 'tmux', 'ubuntu': 'tmux', 'fedora': 'tmux'},
            'zsh': {'arch': 'zsh', 'ubuntu': 'zsh', 'fedora': 'zsh'},
            'docker': {'arch': 'docker', 'ubuntu': 'docker.io', 'fedora': 'docker'},
            'tailscale': {'arch': 'tailscale', 'ubuntu': 'tailscale', 'fedora': 'tailscale'},
            'chromium': {'arch': 'chromium', 'ubuntu': 'chromium-browser', 'fedora': 'chromium'},
            'jellyfin': {'arch': 'jellyfin', 'ubuntu': 'jellyfin', 'fedora': 'jellyfin'},
            'obsidian': {'arch': 'obsidian', 'ubuntu': 'obsidian', 'fedora': 'obsidian'},
            'kitty': {'arch': 'kitty', 'ubuntu': 'kitty', 'fedora': 'kitty'},
            'hyprland': {'arch': 'hyprland', 'ubuntu': 'hyprland (PPA)', 'fedora': 'hyprland (COPR)'},
        }

    def _generate_dotfiles_yml(self, dotfiles: Dict, output_path: Path):
        """Generate dotfiles.yml"""
        self.log("Generating dotfiles.yml...")

        dotfiles_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS home-manager configuration',
                'format_version': '1.0',
                'note': 'Dotfiles to be managed with GNU Stow or similar'
            },
            'apps': dotfiles.get('apps', []),
            'total': dotfiles.get('total', 0),
            'categories': dotfiles.get('categories', {})
        }

        output_file = output_path / 'dotfiles.yml'
        with open(output_file, 'w') as f:
            yaml.dump(dotfiles_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")

    def _generate_system_yml(self, system: Dict, output_path: Path):
        """Generate system.yml"""
        self.log("Generating system.yml...")

        system_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS system configuration',
                'format_version': '1.0'
            },
            'users': system.get('users', []),
            'networking': system.get('networking', {}),
            'firewall': system.get('firewall', {}),
            'filesystems': system.get('filesystems', {})
        }

        output_file = output_path / 'system.yml'
        with open(output_file, 'w') as f:
            yaml.dump(system_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")

    def _generate_secrets_yml(self, secrets: Dict, output_path: Path):
        """Generate secrets.yml"""
        self.log("Generating secrets.yml...")

        secrets_data = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'source': 'NixOS agenix secrets',
                'format_version': '1.0',
                'note': 'Secret inventory (not decrypted) - use for SOPS migration'
            },
            'secrets': secrets.get('secrets', []),
            'total': secrets.get('total', 0),
            'consumers': secrets.get('consumers', {}),
            'categories': secrets.get('categories', {})
        }

        output_file = output_path / 'secrets.yml'
        with open(output_file, 'w') as f:
            yaml.dump(secrets_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {output_file}")
