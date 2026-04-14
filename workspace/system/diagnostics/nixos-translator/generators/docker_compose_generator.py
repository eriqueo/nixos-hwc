"""
Docker Compose Generator - Creates docker-compose.yml from container definitions

Generates:
- docker-compose.yml files organized by stack
- .env.template files for secrets
- Network definitions
- Volume configurations
"""

import yaml
from pathlib import Path
from typing import Dict, List


class DockerComposeGenerator:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose

    def log(self, message):
        if self.verbose:
            print(f"  [docker-compose] {message}")

    def generate(self, containers: List[Dict], output_path: Path, stacks: Dict[str, List[Dict]]):
        """Generate docker-compose files for each stack"""
        self.log(f"Generating Docker Compose files...")

        compose_dir = output_path / 'compose'
        compose_dir.mkdir(parents=True, exist_ok=True)

        # Generate a compose file for each stack
        for stack_name, stack_containers in stacks.items():
            if not stack_containers:
                continue

            self.log(f"Generating compose for {stack_name} stack ({len(stack_containers)} containers)...")

            stack_dir = compose_dir / stack_name
            stack_dir.mkdir(exist_ok=True)

            self._generate_stack_compose(stack_name, stack_containers, stack_dir)

        # Generate master README
        self._generate_compose_readme(compose_dir, stacks)

        self.log(f"✅ Docker Compose files generated at: {compose_dir}")

    def _generate_stack_compose(self, stack_name: str, containers: List[Dict], output_dir: Path):
        """Generate docker-compose.yml for a single stack"""
        compose_data = {
            'version': '3.8',
            'services': {},
            'networks': {},
            'volumes': {}
        }

        secrets_needed = []
        networks_needed = set()

        for container in containers:
            service_name = container['name']
            service_def = self._create_service_definition(container)

            compose_data['services'][service_name] = service_def

            # Track secrets
            if container.get('secrets'):
                secrets_needed.extend(container['secrets'])

            # Track networks
            if 'networks' in service_def:
                networks_needed.update(service_def['networks'])

        # Add network definitions
        if 'media-network' in str(compose_data):
            compose_data['networks']['media-network'] = {
                'driver': 'bridge',
                'name': 'media-network'
            }

        # Write docker-compose.yml
        compose_file = output_dir / 'docker-compose.yml'
        with open(compose_file, 'w') as f:
            yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)

        self.log(f"Created: {compose_file}")

        # Generate .env.template for secrets
        if secrets_needed:
            self._generate_env_template(output_dir, secrets_needed, containers)

        # Generate README for this stack
        self._generate_stack_readme(output_dir, stack_name, containers)

    def _create_service_definition(self, container: Dict) -> Dict:
        """Create a docker-compose service definition from container info"""
        service = {
            'image': container['image'],
            'container_name': container['name'],
            'restart': 'unless-stopped'
        }

        # Environment variables
        if container.get('environment'):
            service['environment'] = container['environment']

        # Ports
        if container.get('ports'):
            service['ports'] = container['ports']

        # Volumes
        if container.get('volumes'):
            service['volumes'] = container['volumes']

        # Network mode
        network_mode = container.get('network_mode', 'media')
        if network_mode == 'vpn':
            # Use gluetun's network namespace
            service['network_mode'] = 'service:gluetun'
        else:
            service['networks'] = ['media-network']

        # Dependencies
        if container.get('depends_on'):
            service['depends_on'] = container['depends_on']

        # GPU configuration
        if container.get('gpu_enabled'):
            service['devices'] = ['/dev/dri:/dev/dri']
            # Could add deploy.resources.reservations.devices for nvidia runtime

        # Capabilities and privileged mode (from extra_options)
        extra_opts = container.get('extra_options', [])
        cap_add = []
        for opt in extra_opts:
            if '--cap-add=' in opt:
                cap = opt.split('=')[1]
                cap_add.append(cap)
            if '--privileged' in opt:
                service['privileged'] = True

        if cap_add:
            service['cap_add'] = cap_add

        # Device mappings
        devices = []
        for opt in extra_opts:
            if '--device=' in opt:
                device = opt.split('=')[1]
                devices.append(device)

        if devices:
            service['devices'] = devices

        # Resource limits (from extra_options)
        for opt in extra_opts:
            if '--memory=' in opt:
                memory = opt.split('=')[1]
                if 'deploy' not in service:
                    service['deploy'] = {'resources': {'limits': {}}}
                service['deploy']['resources']['limits']['memory'] = memory
            if '--cpus=' in opt:
                cpus = opt.split('=')[1]
                if 'deploy' not in service:
                    service['deploy'] = {'resources': {'limits': {}}}
                service['deploy']['resources']['limits']['cpus'] = cpus

        return service

    def _generate_env_template(self, output_dir: Path, secrets: List[Dict], containers: List[Dict]):
        """Generate .env.template file for secrets"""
        env_file = output_dir / '.env.template'

        with open(env_file, 'w') as f:
            f.write("# Environment variables template\n")
            f.write("# Copy this to .env and fill in the values\n\n")

            # Extract unique environment variables that might be secrets
            all_env_vars = set()
            for container in containers:
                env = container.get('environment', {})
                for key, value in env.items():
                    if value == 'CONFIG_VALUE' or 'SECRET' in key.upper() or 'PASSWORD' in key.upper() or 'KEY' in key.upper():
                        all_env_vars.add(key)

            if all_env_vars:
                f.write("# Secrets (fill these in)\n")
                for var in sorted(all_env_vars):
                    f.write(f"{var}=\n")

            f.write("\n# Standard variables\n")
            f.write("PUID=1000\n")
            f.write("PGID=1000\n")
            f.write("TZ=America/Denver\n")

        self.log(f"Created: {env_file}")

    def _generate_stack_readme(self, output_dir: Path, stack_name: str, containers: List[Dict]):
        """Generate README for a specific stack"""
        readme = output_dir / 'README.md'

        content = f"""# {stack_name.replace('-', ' ').title()} Stack

## Services

"""

        for container in containers:
            content += f"### {container['name']}\n"
            content += f"- **Image**: `{container['image']}`\n"

            if container.get('ports'):
                content += f"- **Ports**: {', '.join(container['ports'])}\n"

            if container.get('network_mode'):
                content += f"- **Network**: {container['network_mode']}\n"

            if container.get('gpu_enabled'):
                content += f"- **GPU**: Enabled\n"

            if container.get('depends_on'):
                content += f"- **Depends on**: {', '.join(container['depends_on'])}\n"

            content += "\n"

        content += """## Usage

1. **Configure secrets:**
   ```bash
   cp .env.template .env
   # Edit .env and fill in secret values
   ```

2. **Start the stack:**
   ```bash
   docker-compose up -d
   ```

3. **View logs:**
   ```bash
   docker-compose logs -f
   ```

4. **Stop the stack:**
   ```bash
   docker-compose down
   ```

## Notes

- Ensure `/opt/downloads`, `/mnt/hot`, and `/mnt/media` directories exist
- For GPU acceleration, ensure Docker is configured with GPU runtime
- Check firewall settings for exposed ports
"""

        with open(readme, 'w') as f:
            f.write(content)

        self.log(f"Created: {readme}")

    def _generate_compose_readme(self, compose_dir: Path, stacks: Dict[str, List[Dict]]):
        """Generate master README for all compose stacks"""
        readme = compose_dir / 'README.md'

        content = """# Docker Compose Stacks

This directory contains Docker Compose configurations for all containerized services,
organized by functional stack.

## Stacks

"""

        for stack_name, containers in stacks.items():
            content += f"### {stack_name.replace('-', ' ').title()}\n"
            content += f"- **Location**: `{stack_name}/`\n"
            content += f"- **Services**: {len(containers)} containers\n"
            content += f"- **Containers**: {', '.join(c['name'] for c in containers)}\n\n"

        content += """## Quick Start

Each stack has its own directory with:
- `docker-compose.yml` - Service definitions
- `.env.template` - Environment variables template
- `README.md` - Stack-specific documentation

### Start All Stacks

```bash
# Navigate to each stack directory and start
for stack in */; do
  cd "$stack"
  cp .env.template .env
  # Edit .env as needed
  docker-compose up -d
  cd ..
done
```

### Start Individual Stack

```bash
cd <stack-name>
cp .env.template .env
# Edit .env with your values
docker-compose up -d
```

## Prerequisites

1. **Docker & Docker Compose installed**
   ```bash
   sudo pacman -S docker docker-compose
   sudo systemctl enable --now docker
   sudo usermod -aG docker $USER
   ```

2. **Directory structure:**
   ```bash
   sudo mkdir -p /opt/downloads /opt/arr /mnt/hot /mnt/media
   sudo chown -R $USER:$USER /opt/downloads /opt/arr
   ```

3. **Networks:**
   ```bash
   docker network create media-network
   ```

## GPU Support

For services requiring GPU acceleration (transcoding, AI):

**NVIDIA:**
```bash
# Install nvidia-docker
yay -S nvidia-docker
sudo systemctl restart docker
```

**Intel:**
```bash
# Ensure user is in video/render groups
sudo usermod -aG video,render $USER
```

## Secrets Management

**Option 1: Environment files (.env)**
- Simple, built into Docker Compose
- Copy `.env.template` to `.env` in each stack
- **WARNING**: Never commit .env files to git!

**Option 2: Docker Secrets**
- More secure for production
- Requires Docker Swarm mode

**Option 3: External secrets manager**
- Use SOPS, Vault, or similar
- Inject secrets at runtime

## Networking

**media-network**: Bridge network for inter-container communication
- Most services connect to this network
- Allows services to discover each other by container name

**VPN mode (via Gluetun)**:
- Some containers (qBittorrent) route through Gluetun
- Uses `network_mode: "service:gluetun"`
- Traffic is tunneled through VPN

## Monitoring

```bash
# View all running containers
docker-compose ps

# View logs
docker-compose logs -f [service-name]

# Resource usage
docker stats
```

## Troubleshooting

**Container won't start:**
```bash
docker-compose logs <service>
```

**Permission issues:**
```bash
# Check PUID/PGID in .env matches your user
id $USER

# Fix volume permissions
sudo chown -R $USER:$USER /opt/downloads /mnt/hot /mnt/media
```

**Network issues:**
```bash
# Recreate network
docker network rm media-network
docker network create media-network

# Restart stack
docker-compose down && docker-compose up -d
```

**GPU not detected:**
```bash
# Test GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
# or for Intel
docker run --rm --device=/dev/dri:/dev/dri ubuntu ls -la /dev/dri
```
"""

        with open(readme, 'w') as f:
            f.write(content)

        self.log(f"Created: {readme}")
