"""
Enhanced Container Scanner - Deep extraction of container configurations

Extracts complete container definitions including:
- Images, ports, volumes
- Environment variables
- Network modes and dependencies
- GPU requirements
- Extra options and capabilities
"""

import re
from pathlib import Path
from typing import Dict, List, Optional

import re as _compiled_re

# Fixed patterns compile once; matching stays at the original call sites.
__EXTRACT_FROM_OPTIONS_SEARCH_RE = _compiled_re.compile(r'image\s*=.*?default\s*=\s*"([^"]+)"', _compiled_re.DOTALL)
__EXTRACT_FROM_OPTIONS_SEARCH_RE_2 = _compiled_re.compile(r'network\.mode.*?default\s*=\s*"(\w+)"', _compiled_re.DOTALL)
__EXTRACT_FROM_OPTIONS_SEARCH_RE_3 = _compiled_re.compile(r'gpu\.enable.*?default\s*=\s*(true|false)', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE = _compiled_re.compile(r'image\s*=\s*(?:cfg\.image|"([^"]+)"|(\w+))')
__EXTRACT_FROM_CONFIG_SEARCH_RE_2 = _compiled_re.compile(r'ports\s*=\s*\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE_3 = _compiled_re.compile(r'volumes\s*=\s*\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE_4 = _compiled_re.compile(r'environment\s*=\s*\{([^}]*(?:\{[^}]*\}[^}]*)*)\}', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE_5 = _compiled_re.compile(r'dependsOn\s*=.*?\[\s*"([^"]+)"\s*\]', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE_6 = _compiled_re.compile(r'extraOptions\s*=\s*\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_SEARCH_RE_7 = _compiled_re.compile(r'environmentFiles\s*=\s*\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_FROM_CONFIG_FINDALL_RE = _compiled_re.compile(r'"([^"]+)"')
__EXTRACT_FROM_CONFIG_FINDALL_RE_2 = _compiled_re.compile(r'(\w+)\s*=\s*(?:"([^"]+)"|(\d+)|toString\s+\w+\.(\w+))')



class EnhancedContainerScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.containers = {}

    def log(self, message):
        if self.verbose:
            print(f"  [enhanced-container-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for all container definitions with full details"""
        self.log("Scanning for containers...")

        # Scan domains/server for container definitions
        server_domain = self.source_path / 'domains' / 'server' / 'containers'
        if server_domain.exists():
            for container_dir in server_domain.iterdir():
                if container_dir.is_dir() and not container_dir.name.startswith('_'):
                    self._scan_container_module(container_dir)

        self.log(f"Found {len(self.containers)} container definitions")

        return {
            'containers': list(self.containers.values()),
            'total': len(self.containers)
        }

    def _scan_container_module(self, container_dir: Path):
        """Scan a single container module directory"""
        container_name = container_dir.name
        self.log(f"Scanning {container_name}...")

        container_info = {
            'name': container_name,
            'image': 'unknown',
            'ports': [],
            'volumes': [],
            'environment': {},
            'network_mode': 'media',
            'gpu_enabled': False,
            'depends_on': [],
            'extra_options': [],
            'secrets': [],
            'source_dir': str(container_dir.relative_to(self.source_path))
        }

        # Read options.nix for defaults
        options_file = container_dir / 'options.nix'
        if options_file.exists():
            self._extract_from_options(options_file, container_info)

        # Read parts/config.nix for detailed config
        config_file = container_dir / 'parts' / 'config.nix'
        if config_file.exists():
            self._extract_from_config(config_file, container_info)

        self.containers[container_name] = container_info

    def _extract_from_options(self, file_path: Path, container_info: Dict):
        """Extract information from options.nix"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Extract default image
            image_match = __EXTRACT_FROM_OPTIONS_SEARCH_RE.search(content)
            if image_match:
                container_info['image'] = image_match.group(1)

            # Extract network mode
            network_match = __EXTRACT_FROM_OPTIONS_SEARCH_RE_2.search(content)
            if network_match:
                container_info['network_mode'] = network_match.group(1)

            # Extract GPU setting
            gpu_match = __EXTRACT_FROM_OPTIONS_SEARCH_RE_3.search(content)
            if gpu_match:
                container_info['gpu_enabled'] = gpu_match.group(1) == 'true'

        except Exception as e:
            self.log(f"Error extracting from options: {e}")

    def _extract_from_config(self, file_path: Path, container_info: Dict):
        """Extract detailed configuration from parts/config.nix"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Find the container definition block
            container_pattern = rf'virtualisation\.oci-containers\.containers\.{container_info["name"]}\s*=\s*\{{([^}}]*(?:\{{[^}}]*\}}[^}}]*)*)\}}'
            container_match = re.search(container_pattern, content, re.DOTALL)

            if not container_match:
                return

            config_block = container_match.group(1)

            # Extract image (might override options)
            image_match = __EXTRACT_FROM_CONFIG_SEARCH_RE.search(config_block)
            if image_match and image_match.group(1):
                container_info['image'] = image_match.group(1)

            # Extract ports
            ports_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_2.search(config_block)
            if ports_match:
                ports_text = ports_match.group(1)
                # Find quoted port strings
                port_strings = __EXTRACT_FROM_CONFIG_FINDALL_RE.findall(ports_text)
                container_info['ports'] = port_strings

            # Extract volumes
            volumes_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_3.search(config_block)
            if volumes_match:
                volumes_text = volumes_match.group(1)
                # Find quoted volume strings
                volume_strings = __EXTRACT_FROM_CONFIG_FINDALL_RE.findall(volumes_text)
                container_info['volumes'] = volume_strings

            # Extract environment variables
            env_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_4.search(config_block)
            if env_match:
                env_block = env_match.group(1)
                # Extract key = value pairs
                env_pairs = __EXTRACT_FROM_CONFIG_FINDALL_RE_2.findall(env_block)
                for match in env_pairs:
                    key = match[0]
                    value = match[1] or match[2] or match[3] or 'CONFIG_VALUE'
                    container_info['environment'][key] = value

            # Extract depends_on
            depends_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_5.search(config_block)
            if depends_match:
                container_info['depends_on'] = [depends_match.group(1)]

            # Extract extra options (for GPU, network, capabilities)
            extra_opts_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_6.search(config_block)
            if extra_opts_match:
                extra_text = extra_opts_match.group(1)
                # Find quoted option strings
                option_strings = __EXTRACT_FROM_CONFIG_FINDALL_RE.findall(extra_text)
                container_info['extra_options'] = option_strings

                # Parse extra options for special flags
                for opt in option_strings:
                    if '--network=container:gluetun' in opt or '--network=vpn' in opt:
                        container_info['network_mode'] = 'vpn'
                        if 'gluetun' not in container_info['depends_on']:
                            container_info['depends_on'].append('gluetun')
                    if '/dev/dri' in opt or '/dev/nvidia' in opt:
                        container_info['gpu_enabled'] = True

            # Check for secrets/environment files
            env_file_match = __EXTRACT_FROM_CONFIG_SEARCH_RE_7.search(config_block)
            if env_file_match:
                env_files = __EXTRACT_FROM_CONFIG_FINDALL_RE.findall(env_file_match.group(1))
                container_info['secrets'] = [{'type': 'env_file', 'path': f} for f in env_files]

        except Exception as e:
            self.log(f"Error extracting from config: {e}")

    def categorize_by_stack(self, containers: List[Dict]) -> Dict[str, List[Dict]]:
        """Organize containers into logical stacks"""
        stacks = {
            'downloaders': [],
            'arr-stack': [],
            'media-management': [],
            'infrastructure': [],
            'other': []
        }

        downloader_names = ['gluetun', 'qbittorrent', 'sabnzbd', 'slskd']
        arr_names = ['sonarr', 'radarr', 'lidarr', 'prowlarr', 'bazarr', 'readarr']
        media_mgmt_names = ['jellyseerr', 'tdarr', 'recyclarr', 'organizr', 'soularr', 'beets']
        infra_names = ['caddy', 'ntfy', 'frigate']

        for container in containers:
            name = container['name']

            if name in downloader_names:
                stacks['downloaders'].append(container)
            elif name in arr_names:
                stacks['arr-stack'].append(container)
            elif name in media_mgmt_names:
                stacks['media-management'].append(container)
            elif name in infra_names:
                stacks['infrastructure'].append(container)
            else:
                stacks['other'].append(container)

        # Remove empty stacks
        return {k: v for k, v in stacks.items() if v}
