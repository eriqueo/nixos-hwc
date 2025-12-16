# Pi-hole Network-Wide Ad Blocking Container

Network-wide ad blocking using Pi-hole running in a Podman container.

## Features

- **Network-wide ad blocking** for all devices on your WiFi
- **DNS-based blocking** at the network level (transparent to devices)
- **Web interface** for management, statistics, and configuration
- **Customizable DNS** upstream servers
- **Persistent storage** for configuration and data
- **Automatic port 53 handling** - disables systemd-resolved conflicts

## Charter Compliance

- **Domain**: `domains/server/containers/pihole/` (server workload)
- **Namespace**: `hwc.server.containers.pihole.*`
- **Data location**: `/opt/networking/pihole/` (per Charter container storage pattern)
- **Validation**: Comprehensive assertions for dependencies and conflicts
- **Structure**: `index.nix`, `options.nix`, `sys.nix` pattern

## Quick Start

### 1. Enable in Machine Configuration

Add to your server's `machines/server/config.nix`:

```nix
{
  hwc.server.containers.pihole = {
    enable = true;
    # RECOMMENDED: Use webPasswordFile with agenix secrets
    webPasswordFile = config.age.secrets.pihole-password.path;
    # OR (less secure): webPassword = "your-secure-password";
    timezone = "America/Denver";           # Match your server timezone
  };
}
```

### 2. Rebuild System

```bash
sudo nixos-rebuild switch
```

### 3. Configure Your Router

1. Log into your router's admin interface
2. Find DHCP/DNS settings (location varies by router)
3. Set **Primary DNS** to your server's IP (e.g., `192.168.1.100`)
4. Set **Secondary DNS** to a fallback like `1.1.1.1` or `8.8.8.8`
5. Save and restart router if needed

### 4. Access Web Interface

- URL: `http://<server-ip>:8080/admin`
- Password: The one you set in `webPassword`

## Configuration Options

### Basic Configuration

```nix
{
  hwc.server.containers.pihole = {
    enable = true;

    # Container image (explicit version per CHARTER)
    image = "pihole/pihole:2024.07.0";  # Default, can override

    # Web interface settings
    webPort = 8080;           # Default: 8080

    # RECOMMENDED: Use secrets file (agenix)
    webPasswordFile = config.age.secrets.pihole-password.path;
    # ALTERNATIVE (less secure): webPassword = "secret";

    # DNS settings
    dnsPort = 53;              # Default: 53 (standard DNS port)
    upstreamDns = [            # Default: Cloudflare
      "1.1.1.1"
      "1.0.0.1"
    ];

    # System settings
    timezone = "America/Denver";  # Match your server timezone

    # Automatic port 53 conflict resolution
    disableResolvedStub = true;   # Default: true (disables systemd-resolved)
  };
}
```

### Advanced Configuration

```nix
{
  hwc.server.containers.pihole = {
    enable = true;
    image = "pihole/pihole:2024.07.0";  # Pin to specific version
    webPort = 8080;
    webPasswordFile = config.age.secrets.pihole-password.path;  # Use secrets
    timezone = "America/Denver";

    # Use Google DNS instead of Cloudflare
    upstreamDns = [
      "8.8.8.8"
      "8.8.4.4"
    ];

    # Custom data location (if you have specific storage needs)
    dataDir = "/mnt/media/pihole";
    dnsmasqDir = "/mnt/media/pihole/dnsmasq.d";

    # Extra Pi-hole environment variables
    extraEnvironment = {
      DNSSEC = "true";              # Enable DNSSEC validation
      TEMPERATUREUNIT = "f";        # Show temps in Fahrenheit
      WEBUIBOXEDLAYOUT = "boxed";   # Web UI layout style
      SKIPGRAVITYONBOOT = "1";      # Skip gravity update on boot
    };

    # Manual DNS configuration (advanced)
    disableResolvedStub = false;  # Handle port 53 manually
  };
}
```

## systemd-resolved Port 53 Conflict

**The Problem**: systemd-resolved (enabled by default in NixOS) uses port 53, which Pi-hole also needs.

**The Solution**: This module handles it automatically!

By default (`disableResolvedStub = true`), the module:
1. Disables systemd-resolved's DNS stub listener on port 53
2. Configures the system to use Pi-hole (127.0.0.1) for DNS
3. Frees port 53 for Pi-hole to use

If you prefer manual configuration, set `disableResolvedStub = false` and configure DNS yourself.

## Router Configuration Guide

### Finding Your Router's DNS Settings

Common locations by router type:

- **TP-Link**: Network → DHCP Server → Primary/Secondary DNS
- **Netgear**: Advanced → Setup → LAN Setup → DNS Server
- **Linksys**: Connectivity → Local Network → DHCP Server
- **Asus**: LAN → DHCP Server → DNS Server
- **UniFi**: Settings → Networks → Edit Network → DHCP Name Server

### What to Set

1. **Primary DNS**: Your server's IP address (find with `ip addr show`)
2. **Secondary DNS**: A fallback like `1.1.1.1` or `8.8.8.8`

**Note**: Some devices may cache DNS settings. Restart them or disconnect/reconnect to WiFi.

## Firewall Integration

The module automatically opens required ports:
- **TCP/UDP 53**: DNS queries
- **TCP 8080**: Web interface (or your custom `webPort`)

This integrates with `hwc.networking.firewall` automatically.

## Management

### Check Container Status

```bash
# Check if running
sudo podman ps | grep pihole

# View logs
sudo podman logs pihole

# Follow logs live
sudo podman logs -f pihole
```

### Restart Container

```bash
sudo systemctl restart podman-pihole.service
```

### Update Pi-hole

**CHARTER Compliance**: This module uses explicit version pinning (not `:latest`) for reproducibility.

**⚠️  CRITICAL: v5 → v6 Migration Warning**

Pi-hole v6 (starting with 2024.xx.x versions after mid-2024) makes **irreversible** changes to configuration files. Per the official Docker Pi-hole documentation:

> "Upgrading from v5 to v6 will update your config files and the changes are irreversible."

**Before updating from v5 to v6:**

```bash
# 1. BACKUP YOUR DATA (REQUIRED)
sudo tar -czf /tmp/pihole-backup-$(date +%F).tar.gz ${cfg.dataDir} ${cfg.dnsmasqDir}

# 2. Store backup safely
mv /tmp/pihole-backup-*.tar.gz /mnt/media/backups/

# 3. Verify backup integrity
tar -tzf /mnt/media/backups/pihole-backup-*.tar.gz | head
```

**Update procedure:**

```bash
# 1. Check current version
sudo podman inspect pihole | grep -i "pihole/pihole"

# 2. Check for new versions at https://github.com/pi-hole/docker-pi-hole/releases

# 3. Update the image option in your config
# machines/server/config.nix or domains/server/containers/pihole/options.nix
hwc.server.containers.pihole.image = "pihole/pihole:2024.08.0";  # New version

# 4. Rebuild NixOS
sudo nixos-rebuild switch

# 5. Verify new version and functionality
sudo podman inspect pihole | grep Image
curl http://localhost:8080/admin  # Check web UI loads
```

**Rollback (if needed):**
```bash
# Stop container
sudo systemctl stop podman-pihole

# Restore from backup
sudo rm -rf ${cfg.dataDir} ${cfg.dnsmasqDir}
sudo tar -xzf /mnt/media/backups/pihole-backup-YYYY-MM-DD.tar.gz -C /

# Revert image version in config
# hwc.server.containers.pihole.image = "pihole/pihole:2024.07.0";  # Old version
sudo nixos-rebuild switch
```

**Note**: Avoid using `:latest` tag as it breaks reproducibility (CHARTER requirement).

**Advanced: SHA256 Digest Pinning**

For maximum reproducibility (tags can be re-pointed, digests cannot), use digest pinning:

```nix
hwc.server.containers.pihole.image = "pihole/pihole@sha256:abcd1234...";  # Immutable
```

Find digests at https://hub.docker.com/r/pihole/pihole/tags - click on a tag to see its digest.

### Access Shell Inside Container

```bash
sudo podman exec -it pihole bash
```

## Web Interface Features

Access at `http://<server-ip>:8080/admin`:

- **Dashboard**: Real-time stats, queries blocked, clients
- **Query Log**: See all DNS queries in real-time
- **Blocklists**: Add/remove ad-blocking lists
- **Whitelist/Blacklist**: Fine-tune what gets blocked
- **Local DNS**: Set custom DNS records for your network
- **Settings**: Configure Pi-hole behavior

## Testing Pi-hole

### Test DNS Resolution

From any computer on your network:

```bash
# Should use Pi-hole
nslookup google.com

# Test if ads are blocked
nslookup doubleclick.net  # Should return 0.0.0.0 if blocked
```

### Test from Server

```bash
# Should use local Pi-hole
nslookup google.com 127.0.0.1
```

## Troubleshooting

### Container Won't Start

```bash
# Check service status
sudo systemctl status podman-pihole.service

# View detailed logs
sudo journalctl -u podman-pihole.service -n 50

# Check if port 53 is available
sudo ss -tlnp | grep :53
```

### DNS Not Working

1. **Verify Pi-hole is running**: `sudo podman ps | grep pihole`
2. **Check firewall**: `sudo iptables -L -n | grep 53`
3. **Test DNS locally**: `nslookup google.com 127.0.0.1`
4. **Check router settings**: Verify DNS is set to server IP
5. **Restart devices**: Some devices cache DNS settings

### Web Interface Not Accessible

1. **Verify port**: `sudo ss -tlnp | grep 8080` (or your custom port)
2. **Check firewall**: Ensure port is open
3. **Try from server**: `curl http://localhost:8080/admin`
4. **Check container logs**: `sudo podman logs pihole`

### Port 53 Still Conflicting

If you're getting port 53 conflicts despite `disableResolvedStub = true`:

```bash
# Check what's using port 53
sudo ss -tlnp | grep :53

# If systemd-resolved is still there
sudo systemctl status systemd-resolved

# Check resolved config
cat /etc/systemd/resolved.conf

# May need to restart after rebuild
sudo systemctl restart systemd-resolved
```

### Pi-hole Not Blocking Ads

1. **Wait for gravity update**: First boot updates blocklists (takes time)
2. **Check blocklists**: Web interface → Group Management → Adlists
3. **Update gravity manually**:
   ```bash
   sudo podman exec pihole pihole -g
   ```
4. **Check query log**: Verify queries are reaching Pi-hole
5. **Verify router DNS**: Double-check router is using server IP

## Data Persistence

All Pi-hole data is stored in:
- **Main data**: `/opt/networking/pihole/` (or your custom `dataDir`)
- **DNS config**: `/opt/networking/pihole/dnsmasq.d/` (or your custom `dnsmasqDir`)

This persists across:
- Container restarts
- System reboots
- Pi-hole updates
- NixOS rebuilds

## Security Considerations

### Password Security

**CRITICAL**: Always use a secure password!

**RECOMMENDED**: Use agenix secrets management with `webPasswordFile`:

This implementation uses **runtime environment file generation** to prevent secrets from leaking into the Nix store. The password is read from `/run/agenix` at boot time (after agenix decrypts it), not during Nix evaluation.

```nix
# Step 1: Create encrypted secret
# echo "your-secure-password" | age -r <pubkey> > domains/secrets/parts/server/pihole-password.age

# Step 2: Declare in domains/secrets/declarations/server.nix
age.secrets.pihole-password = {
  file = ../../parts/server/pihole-password.age;
  mode = "0440";
  group = "secrets";
};

# Step 3: Use in Pi-hole config (CHARTER-compliant: no Nix store leaks)
hwc.server.containers.pihole = {
  enable = true;
  webPasswordFile = config.age.secrets.pihole-password.path;  # /run/agenix/pihole-password
};
```

**How it works:**
1. `agenix.service` runs at boot, decrypting secrets to `/run/agenix/`
2. `pihole-env-setup.service` runs after agenix, reading the decrypted password and generating `${dataDir}/.env`
3. `podman-pihole.service` starts with `environmentFiles = ["${dataDir}/.env"]`, reading the password at container start
4. **No secrets in Nix store** - password never evaluated during `nixos-rebuild`

**ALTERNATIVE** (less secure): Use `webPassword` for testing only:
```nix
# WARNING: This stores the password in the Nix store (world-readable)
# Only use for testing, never for production
hwc.server.containers.pihole.webPassword = "test-only-password";
```

### Network Exposure

- Web interface is accessible to **anyone on your network**
- Ensure your **WiFi is secured** with WPA3/WPA2
- Consider **firewall rules** to restrict web interface access
- Pi-hole **logs all DNS queries** - consider privacy implications

### DNS Security

- **DNSSEC**: Enable with `extraEnvironment.DNSSEC = "true";`
- **Upstream DNS**: Choose privacy-respecting providers
  - Cloudflare: `1.1.1.1` (default, privacy-focused)
  - Quad9: `9.9.9.9` (security-focused)
  - Google: `8.8.8.8` (widely cached)

## Customization & Tweaking

### Change Web Port

If port 8080 conflicts with other services:

```nix
hwc.server.containers.pihole.webPort = 8888;  # Or any free port
```

### Use Different DNS Providers

```nix
hwc.server.containers.pihole.upstreamDns = [
  "9.9.9.9"    # Quad9
  "149.112.112.112"  # Quad9 secondary
];
```

### Customize Data Location

```nix
hwc.server.containers.pihole = {
  dataDir = "/mnt/media/pihole";  # Use different storage
  dnsmasqDir = "/mnt/media/pihole/dnsmasq.d";
};
```

### Add Custom Blocklists

Via web interface:
1. Go to Group Management → Adlists
2. Add your custom list URLs
3. Update gravity: Tools → Update Gravity

### Local DNS Records

Use Pi-hole to set custom DNS for your network:
1. Web interface → Local DNS → DNS Records
2. Add domain → IP mappings
3. Example: `server.local` → `192.168.1.100`

## Dependencies

This module requires:
- **Podman**: Enabled via `hwc.infrastructure.virtualization.enable`
- **Networking**: `hwc.networking.enable` for firewall management
- **systemd-resolved**: Will be auto-configured to avoid conflicts

All dependencies are validated at build time via Charter-compliant assertions.

## Integration with Other Services

### Using Pi-hole as System DNS

Already done automatically when `disableResolvedStub = true`!

### Caddy Reverse Proxy

To expose Pi-hole via Caddy at a custom domain:

```nix
services.caddy.virtualHosts."pihole.example.com".extraConfig = ''
  reverse_proxy localhost:8080
'';
```

### Monitoring Integration

Pi-hole provides metrics at `http://localhost:8080/admin/api.php`

## See Also

- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Pi-hole GitHub](https://github.com/pi-hole/pi-hole)
- Charter compliance: See `/docs/CHARTER.md`
- Container patterns: See `domains/server/containers/README.md`
