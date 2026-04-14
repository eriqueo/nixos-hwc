# Mailbot Quick Start Guide

Step-by-step instructions to get mailbot running on your system.

## Prerequisites

✅ You already have:
- OAuth credentials (`credentials.json`) from Google Cloud Console
- Python 3.11+ available on your system

## Setup Steps

### 1. Navigate to Project Directory

```bash
cd ~/.nixos/workspace/projects/mailbot
```

### 2. Create Virtual Environment

```bash
python3 -m venv .venv
```

This creates an isolated Python environment in `.venv/` directory.

### 3. Activate Virtual Environment

```bash
source .venv/bin/activate
```

Your shell prompt should change to show `(.venv)` prefix.

**Note:** You'll need to run this activation command each time you open a new terminal.

### 4. Install Dependencies

```bash
pip install -e ".[dev]"
```

This installs:
- `google-api-python-client` - Gmail API access
- `google-auth` - OAuth authentication
- `google-auth-oauthlib` - OAuth flow handling
- `requests` - HTTP requests for unsubscribe links
- `pytest`, `ruff` - Development tools

### 5. Verify Installation

```bash
mailbot --help
```

You should see the help text with available options.

## First Run (OAuth Setup)

### Test with Dry-Run Mode

```bash
mailbot --dry-run --max 50
```

**What happens:**
1. **Browser opens** automatically for Google OAuth consent screen
2. **Sign in** with your Google account
3. **Authorize** mailbot to access Gmail (read, modify, send)
4. Browser shows "The authentication flow has completed"
5. Terminal shows mailbot processing (no actual changes in dry-run mode)

**Result:**
- `token.json` file is created in project directory
- This token is used for all future runs (no browser needed)
- Token expires after ~7 days, but auto-refreshes when used

## Usage Examples

### Dry-Run (No Changes)

Test what mailbot would do without making any changes:

```bash
# Test on promotional emails (default)
mailbot --dry-run --max 50

# Test on specific sender
mailbot --dry-run --query "from:newsletters@example.com"

# Test on old unread emails
mailbot --dry-run --query "is:unread older_than:6m"
```

### Process Emails (Archive)

Actually process emails and archive them:

```bash
# Process 100 promotional emails (removes from inbox, keeps in All Mail)
mailbot --max 100

# Process specific sender
mailbot --query "from:marketing@company.com" --max 50

# Process old promotional emails
mailbot --query "category:promotions older_than:1y" --max 500
```

### Process Emails (Delete)

Permanently delete emails instead of archiving:

```bash
# Delete promotional emails
mailbot --delete --max 100

# Delete old newsletters
mailbot --delete --query "from:newsletter@ older_than:1y"
```

**⚠️ Warning:** `--delete` permanently removes emails. Use `--dry-run` first to verify!

## Common Queries

```bash
# All promotional emails in inbox
--query "category:promotions in:inbox"

# Unread promotions only
--query "category:promotions is:unread"

# Specific sender
--query "from:newsletters@example.com"

# Older than 6 months
--query "older_than:6m"

# Multiple conditions
--query "from:marketing@ older_than:1y in:inbox"

# Exclude specific label
--query "category:promotions -label:important"
```

See [Gmail search operators](https://support.google.com/mail/answer/7190) for more options.

## Activation Helper Script

To avoid typing `source .venv/bin/activate` every time, create an alias:

```bash
# Add to ~/.zshrc or ~/.bashrc
alias mailbot-activate='cd ~/.nixos/workspace/projects/mailbot && source .venv/bin/activate'
```

Then just run:
```bash
mailbot-activate
mailbot --dry-run --max 50
```

## Typical Workflow

```bash
# 1. Activate environment
cd ~/.nixos/workspace/projects/mailbot
source .venv/bin/activate

# 2. Dry-run to see what would happen
mailbot --dry-run --max 100

# 3. Review output, then run for real
mailbot --max 100

# 4. Check results in Gmail web interface

# 5. Deactivate virtualenv when done
deactivate
```

## Automated Cleanup (Optional)

For scheduled weekly cleanup, see `systemd-example.service` and `systemd-example.timer` in this directory.

Copy to `~/.config/systemd/user/` and enable:

```bash
# Copy files
cp systemd-example.service ~/.config/systemd/user/mailbot-cleanup.service
cp systemd-example.timer ~/.config/systemd/user/mailbot-cleanup.timer

# Enable and start timer
systemctl --user daemon-reload
systemctl --user enable --now mailbot-cleanup.timer

# Check status
systemctl --user list-timers
```

## Troubleshooting

### "credentials.json not found"

Make sure `credentials.json` exists in the project directory:
```bash
ls -la ~/.nixos/workspace/projects/mailbot/credentials.json
```

If missing, copy from your credentials location:
```bash
cp ~/path/to/client_secret_*.json ~/.nixos/workspace/projects/mailbot/credentials.json
```

### "ModuleNotFoundError: No module named 'requests'"

Virtual environment not activated. Run:
```bash
source .venv/bin/activate
```

### OAuth browser doesn't open

Copy the URL from terminal output and paste into browser manually.

### Token expired

Delete `token.json` and run mailbot again to re-authenticate:
```bash
rm token.json
mailbot --dry-run --max 10
```

### Rate limiting / API quota errors

Gmail API has rate limits. If you hit them:
- Reduce `--max` value (use smaller batches)
- Wait 1-2 hours between runs
- Process in multiple smaller runs instead of one large run

## Security Notes

- ✅ `credentials.json` and `token.json` are gitignored (never committed)
- ✅ OAuth tokens auto-refresh (no password storage)
- ✅ Tokens expire after ~7 days of inactivity
- ✅ You can revoke access at [Google Account Security](https://myaccount.google.com/permissions)

## Need Help?

See full documentation in `README.md` for:
- Detailed Gmail query syntax
- Systemd automation setup
- Future NixOS integration plans
- Development and testing instructions

---

**Ready to clean up your inbox!** 🧹📧
