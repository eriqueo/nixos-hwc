# Mailbot — Gmail Bulk Unsubscribe Automation

Automated tool to bulk unsubscribe from promotional emails and clean up your Gmail inbox.

## Features

- 🔍 **Smart Detection** - Extracts unsubscribe links from email headers and HTML body
- 📧 **Dual Method** - Handles both `mailto:` and HTTP unsubscribe links
- 🔒 **Secure OAuth** - Uses Google OAuth 2.0 (no password storage)
- 🧪 **Dry-run Mode** - Test before making changes
- 📊 **Progress Tracking** - Real-time progress updates every 50 messages
- 🗂️ **Flexible Actions** - Archive or delete processed messages
- 🎯 **Custom Queries** - Filter by labels, dates, senders, etc.

## Quick Start

### 1. Development Setup

```bash
# Enter the development shell
cd ~/.nixos/workspace/projects/mailbot
nix-shell

# The shell will auto-create a virtualenv and install dependencies
```

### 2. Google OAuth Setup

You need to create OAuth credentials from Google Cloud Console:

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**

2. **Create a new project** (or select existing)
   - Name: "Mailbot" or "Gmail Cleanup"

3. **Enable Gmail API**
   - Navigation menu → APIs & Services → Library
   - Search "Gmail API" → Enable

4. **Create OAuth Credentials**
   - APIs & Services → Credentials
   - Click "Create Credentials" → OAuth client ID
   - Application type: **Desktop app**
   - Name: "Mailbot CLI"
   - Download JSON

5. **Save credentials**
   ```bash
   # Rename downloaded file and place in project directory
   mv ~/Downloads/client_secret_*.json ~/.nixos/workspace/projects/mailbot/credentials.json
   ```

### 3. First Run (Test with Dry-run)

```bash
# Test with default query (promotional emails)
mailbot --dry-run

# Test with custom query
mailbot --query "from:newsletters@example.com" --dry-run

# Test with limited results
mailbot --max 50 --dry-run
```

On first run, a browser will open for OAuth consent. After approving, a `token.json` file is created for future runs.

## Usage

### Basic Commands

```bash
# Process all promotional emails (archive to All Mail)
mailbot

# Process and delete instead of archive
mailbot --delete

# Process specific query
mailbot --query "from:spam@example.com older_than:1y"

# Limit number of messages
mailbot --max 1000

# Dry-run to see what would happen
mailbot --dry-run
```

### Gmail Query Examples

```bash
# All promotional emails in inbox
mailbot --query "category:promotions in:inbox"

# Unread promotions only
mailbot --query "category:promotions is:unread"

# Specific sender
mailbot --query "from:newsletters@company.com"

# Older than 6 months
mailbot --query "category:promotions older_than:6m"

# Multiple conditions
mailbot --query "from:marketing@example.com older_than:1y in:inbox"
```

See [Gmail search operators](https://support.google.com/mail/answer/7190) for more query options.

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--query` | Gmail search query | `category:promotions in:inbox` |
| `--delete` | Delete messages instead of archive | Archive |
| `--dry-run` | Show what would happen without changes | Disabled |
| `--max` | Maximum messages to process | 10000 |

## How It Works

1. **Authenticate** - Uses OAuth 2.0 to access your Gmail
2. **Search** - Finds messages matching your query
3. **Extract Links** - Looks for unsubscribe methods:
   - `List-Unsubscribe` email header
   - HTML body links containing "unsubscribe"
4. **Unsubscribe** - Attempts to unsubscribe via:
   - Sending email to `mailto:` links
   - HTTP GET/POST to web unsubscribe URLs
5. **Archive/Delete** - Removes message from inbox

## Systemd Service (Optional)

For automated scheduled cleanup, create a systemd user service:

### Create Service File

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/mailbot-cleanup.service <<'EOF'
[Unit]
Description=Gmail bulk unsubscribe cleanup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=%h/.nixos/workspace/projects/mailbot
ExecStart=%h/.nixos/workspace/projects/mailbot/.venv/bin/mailbot --max 500
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
```

### Create Timer File

```bash
cat > ~/.config/systemd/user/mailbot-cleanup.timer <<'EOF'
[Unit]
Description=Run mailbot cleanup weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

### Enable and Start

```bash
# Reload systemd user services
systemctl --user daemon-reload

# Enable timer (runs weekly)
systemctl --user enable mailbot-cleanup.timer
systemctl --user start mailbot-cleanup.timer

# Check status
systemctl --user list-timers
systemctl --user status mailbot-cleanup.timer

# Manual test run
systemctl --user start mailbot-cleanup.service
journalctl --user -u mailbot-cleanup.service -f
```

## NixOS Integration (Future)

For system-wide deployment, a NixOS module could be added to `domains/home/apps/mailbot/`:

```nix
# domains/home/apps/mailbot/index.nix (future)
{ config, lib, pkgs, ... }:

let
  mailbot = pkgs.python3Packages.buildPythonApplication {
    pname = "hwc-mailbot";
    version = "0.2.0";
    src = ../../../../workspace/projects/mailbot;
    # ...
  };
in
{
  options.hwc.home.apps.mailbot = {
    enable = lib.mkEnableOption "Gmail bulk unsubscribe automation";
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Systemd timer schedule";
    };
  };

  config = lib.mkIf config.hwc.home.apps.mailbot.enable {
    home.packages = [ mailbot ];
    systemd.user.services.mailbot-cleanup = {
      # ...
    };
  };
}
```

## Charter Compliance

✅ **No secrets in repository**
- `credentials.json` and `token.json` are gitignored
- OAuth credentials must be obtained from Google Cloud Console
- For production deployment, use agenix secrets (see `domains/secrets/`)

✅ **Workspace organization**
- Located in `workspace/projects/` (user development tools)
- Self-contained with reproducible dev environment
- No coupling to core system domains

## Security Notes

- **OAuth 2.0** - No password storage, uses secure token-based auth
- **Token refresh** - Automatically refreshes expired tokens
- **Scopes** - Only requests necessary Gmail permissions:
  - `gmail.modify` - Archive/delete messages
  - `gmail.send` - Send unsubscribe emails
  - `gmail.readonly` - Read message content
- **Local storage** - Credentials and tokens stored locally (not committed)

## Troubleshooting

### Browser doesn't open for OAuth

If the OAuth consent screen doesn't open automatically:

```bash
# The script will print a URL - copy and paste into browser manually
mailbot --dry-run
```

### "credentials.json not found"

You need to create OAuth credentials from Google Cloud Console (see setup instructions above).

### HTTP unsubscribe links fail

Some unsubscribe links require:
- User-Agent header (already included)
- Browser cookies/session (not supported - use web browser manually for these)
- CAPTCHAs (not supported)

The script will log failures - you can manually visit these URLs if needed.

### Rate limiting

If processing thousands of emails, Gmail API may rate-limit:
- Use `--max` to process in batches
- Run multiple times instead of one large batch
- Wait a few minutes between runs

## Development

### Running Tests

```bash
nix-shell
pytest                     # Run all tests
pytest -v                  # Verbose output
pytest --cov=mailbot       # Coverage report
```

### Code Quality

```bash
# Lint code
ruff check src/

# Format code
ruff format src/

# Type checking (if mypy added)
mypy src/
```

### Adding Features

Ideas for future enhancements:

- 📊 Statistics/reporting (CSV export of processed emails)
- 🏷️ Smart labeling (auto-categorize before archiving)
- 🔌 Integration with other email services (Outlook, ProtonMail)
- 📧 Batch mailto support (combine into single email)
- 🧠 ML-based sender analysis (identify patterns)
- 📱 Notification integration (ntfy for completion status)

## Related Projects

- **Email Infrastructure**: `domains/home/mail/` - Proton Bridge, IMAP sync, local mail clients
- **Workspace Projects**: `workspace/projects/` - Other user development tools

## License

MIT License - See project root for details

## Author

Eric @ Heartwood Craft

---

**Note**: This tool modifies your Gmail. Always test with `--dry-run` first and start with small batches (`--max 50`) to verify behavior.
