# ntfy Notification System

**Domain**: `hwc.system.services.ntfy`
**Location**: `domains/system/services/ntfy/`
**Purpose**: Centralized notification system for cross-machine and cross-service alerts using [ntfy](https://ntfy.sh)

---

## Overview

This module provides a reusable ntfy notification system that can be used across all machines (laptop, server) and by any service (backups, monitoring, systemd units, etc.). It installs a CLI tool `hwc-ntfy-send` that sends notifications via curl to an ntfy server.

### Key Features

- **Host-agnostic**: Configure per machine with different topics and settings
- **Reusable**: Any service or script can call `hwc-ntfy-send`
- **Secure**: Supports authentication via token or basic auth using file-based secrets
- **Flexible**: Default settings with per-notification overrides
- **Automatic tagging**: Optional hostname tagging for multi-machine setups

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  hwc.system.services.ntfy (module configuration)            │
│  - serverUrl, defaultTopic, tags, auth                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─► hwc-ntfy-send (CLI tool)
                       │   - Installed in PATH
                       │   - Reads module config
                       │   - Sends via curl
                       │
                       └─► Used by:
                           - Backup system (local, cloud)
                           - Systemd services (OnFailure, ExecStartPost)
                           - Custom scripts and monitoring
```

---

## Installation

The module is automatically imported via `domains/system/services/index.nix`. Simply enable it in your machine configuration.

### Basic Configuration (Laptop)

```nix
# machines/laptop/config.nix
{
  hwc.system.services.ntfy = {
    enable = true;
    serverUrl = "https://ntfy.sh";
    defaultTopic = "hwc-laptop-events";
    defaultTags = [ "hwc" "laptop" ];
    defaultPriority = 3;
    hostTag = true;  # Adds "host-hwc-laptop" tag automatically

    # Auth disabled for public topics (or enable for private)
    auth.enable = false;
  };
}
```

### Basic Configuration (Server)

```nix
# machines/server/config.nix
{
  hwc.system.services.ntfy = {
    enable = true;
    serverUrl = "https://ntfy.sh";
    defaultTopic = "hwc-server-events";
    defaultTags = [ "hwc" "server" "production" ];
    defaultPriority = 4;  # Higher priority for server alerts
    hostTag = true;

    auth.enable = false;
  };
}
```

### Configuration with Authentication

For private topics, enable authentication using agenix secrets:

```nix
# machines/laptop/config.nix
{
  hwc.system.services.ntfy = {
    enable = true;
    serverUrl = "https://ntfy.sh";
    defaultTopic = "hwc-private";
    defaultTags = [ "hwc" "private" ];
    hostTag = true;

    # Token authentication (recommended)
    auth = {
      enable = true;
      method = "token";
      tokenFile = "/run/secrets/ntfy-token";  # Managed by agenix
    };
  };

  # Agenix secret declaration (if using agenix)
  age.secrets.ntfy-token = {
    file = ../../domains/secrets/parts/ntfy/token.age;
    mode = "0440";
    group = "secrets";
  };
}
```

Alternatively, use basic authentication:

```nix
auth = {
  enable = true;
  method = "basic";
  userFile = "/run/secrets/ntfy-user";
  passFile = "/run/secrets/ntfy-pass";
};
```

---

## Usage

### CLI Tool: `hwc-ntfy-send`

Once the module is enabled, the `hwc-ntfy-send` command is available system-wide.

#### Basic Usage

```bash
# Send to default topic (configured in module)
hwc-ntfy-send - "Backup Complete" "All files backed up successfully"

# Send to specific topic
hwc-ntfy-send backup-alerts "Backup Failed" "Check /var/log/backup"

# Send message without title
hwc-ntfy-send alerts - "This is just a message body"

# Add extra tags
hwc-ntfy-send --tag urgent,critical alerts "System Down" "Server unreachable"

# Set priority (1=min, 5=max)
hwc-ntfy-send --priority 5 alerts "CRITICAL" "Disk space at 95%"

# Combine options
hwc-ntfy-send --tag backup --priority 4 - "Weekly Backup" "Completed in 2h 15m"
```

#### Help

```bash
hwc-ntfy-send --help
```

---

## Integration Examples

### Backup System Integration

The ntfy module integrates seamlessly with the backup system. Configure both modules:

```nix
# profiles/system.nix or machines/laptop/config.nix
{
  # Enable ntfy
  hwc.system.services.ntfy = {
    enable = true;
    defaultTopic = "hwc-backups";
    defaultTags = [ "hwc" "backup" ];
    hostTag = true;
  };

  # Enable backup with ntfy notifications
  hwc.system.services.backup = {
    enable = true;

    local.enable = true;

    notifications = {
      enable = true;
      onSuccess = false;  # Only notify on failure
      onFailure = true;

      # Enable ntfy notifications
      ntfy = {
        enable = true;
        topic = null;  # Use default topic from ntfy module
      };
    };
  };
}
```

You can override the topic per backup type:

```nix
hwc.system.services.backup.notifications.ntfy = {
  enable = true;
  topic = "hwc-critical-backups";  # Override default topic
};
```

### Systemd Service Integration

Use ntfy notifications in any systemd service:

```nix
systemd.services.my-service = {
  description = "My Service";
  script = ''
    # Do work...

    # Send notification on success
    hwc-ntfy-send - "Service Success" "my-service completed"
  '';

  # Send notification on failure
  onFailure = [ "notify-ntfy-failure@%n.service" ];
};

# Generic failure notification service
systemd.services."notify-ntfy-failure@" = {
  description = "Send ntfy notification on service failure";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = ''
      ${pkgs.bash}/bin/bash -c 'hwc-ntfy-send --priority 5 --tag failure - "Service Failed" "Service %i failed"'
    '';
  };
};
```

### Custom Script Integration

```bash
#!/usr/bin/env bash
# my-script.sh

set -euo pipefail

# Run your task
if some_command; then
  hwc-ntfy-send - "Task Success" "The task completed successfully"
  exit 0
else
  hwc-ntfy-send --priority 5 --tag error - "Task Failed" "The task encountered an error"
  exit 1
fi
```

### Monitoring and Health Checks

```nix
# Example: disk space monitor
systemd.timers.disk-space-check = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
  };
};

systemd.services.disk-space-check = {
  script = ''
    USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$USAGE" -gt 90 ]; then
      hwc-ntfy-send --priority 5 --tag disk,critical \
        - "Disk Space Critical" \
        "Root filesystem at ''${USAGE}% capacity"
    fi
  '';
};
```

---

## Configuration Options

### `hwc.system.services.ntfy`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable ntfy notification system |
| `serverUrl` | string | `"https://ntfy.sh"` | ntfy server URL (public or self-hosted) |
| `defaultTopic` | string or null | `null` | Default topic for notifications |
| `defaultTags` | list of strings | `[]` | Default tags applied to all notifications |
| `defaultPriority` | int/string or null | `null` | Default priority (1-5) |
| `hostTag` | bool | `true` | Automatically add hostname as tag |

### `hwc.system.services.ntfy.auth`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable authentication |
| `method` | enum | `"token"` | Authentication method: `"token"` or `"basic"` |
| `tokenFile` | path or null | `null` | Path to token file (for token auth) |
| `userFile` | path or null | `null` | Path to username file (for basic auth) |
| `passFile` | path or null | `null` | Path to password file (for basic auth) |

---

## Testing

### Test the CLI Tool

After enabling the module and rebuilding:

```bash
# Check if tool is installed
which hwc-ntfy-send

# Test with a public topic (uses ntfy.sh public server)
hwc-ntfy-send test-topic-$(whoami) "Test Notification" "This is a test from hwc-ntfy-send"

# Check the notification at https://ntfy.sh/test-topic-<yourusername>
```

### Test Backup Integration

```bash
# Trigger a manual backup (if configured)
sudo systemctl start backup-local

# Check logs
journalctl -u backup-local -f

# Verify notification was sent (check ntfy topic)
```

### Debug Mode

To see what the CLI tool is doing:

```bash
# Check configuration
hwc-ntfy-send --help

# Test with verbose curl output (modify the script temporarily)
# Or check journalctl for service logs
```

---

## Security Considerations

1. **Public Topics**: Anyone can subscribe to public topics on ntfy.sh. Use authentication for sensitive notifications.

2. **Secret Management**: Never commit secrets to git. Use agenix or other secret management:
   ```bash
   # Encrypt a token with agenix
   echo "your-ntfy-token" | age -r <pubkey> > domains/secrets/parts/ntfy/token.age
   ```

3. **File Permissions**: Secret files should be readable only by root or the service group:
   ```nix
   age.secrets.ntfy-token = {
     file = ./path/to/token.age;
     mode = "0440";
     group = "secrets";
   };
   ```

4. **Self-hosted ntfy**: For production, consider self-hosting ntfy:
   ```nix
   hwc.system.services.ntfy.serverUrl = "https://ntfy.yourdomain.com";
   ```

---

## Troubleshooting

### Notifications Not Sending

1. Check if the module is enabled:
   ```bash
   nix eval .#nixosConfigurations.hwc-laptop.config.hwc.system.services.ntfy.enable
   ```

2. Check if `hwc-ntfy-send` is in PATH:
   ```bash
   which hwc-ntfy-send
   ```

3. Test manually:
   ```bash
   hwc-ntfy-send test "Test" "Manual test"
   ```

4. Check authentication files exist and are readable:
   ```bash
   sudo ls -la /run/secrets/ntfy-*
   ```

### Authentication Errors

- Verify tokenFile/userFile/passFile paths are correct
- Ensure secret files are decrypted by agenix (check `/run/secrets/`)
- Check file permissions (mode 0440, group secrets)

### Topic Not Found

- If using default topic, ensure `defaultTopic` is set in configuration
- Otherwise, explicitly specify topic in CLI call

---

## Future Enhancements

Potential improvements for future iterations:

- [ ] Support for ntfy attachments
- [ ] Support for ntfy actions (buttons)
- [ ] Support for ntfy scheduling (delayed notifications)
- [ ] Wrapper functions for common notification patterns
- [ ] Integration with more services (monitoring, CI/CD)
- [ ] Rate limiting configuration
- [ ] Retry logic with exponential backoff

---

## References

- [ntfy.sh Documentation](https://docs.ntfy.sh/)
- [ntfy Server API](https://docs.ntfy.sh/publish/)
- [Backup Module](../backup/README.md)
- [CHARTER.md](../../../../CHARTER.md)

---

**Version**: 1.0
**Last Updated**: 2025-11-21
**Maintainer**: Eric (with AI assistance)
