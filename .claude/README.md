# Claude Code Optimization Setup

This directory contains configurations to make Claude Code more token-efficient and prevent data loss.

## 🚀 Slash Commands

Use these commands to save tokens by avoiding repetitive prompts:

- `/build` - Build NixOS config and check for errors
- `/check` - Run comprehensive syntax and validation checks
- `/cp` - Commit AND push in one operation (prevents lost commits!)
- `/status` - Show git status with unpushed commit warnings
- `/update` - Update flake inputs and verify build

**Usage:** Just type `/build` in Claude Code instead of "please build my config"

## 🔧 MCP Servers

MCP servers provide external capabilities without token overhead.

### Machine-Specific Configuration

This repo has **different MCP configs for laptop vs server**:
- `.mcp.laptop.json` - Laptop (development workstation)
- `.mcp.server.json` - Server (infrastructure services)

**Setup for your machine:**
```bash
bash .claude/setup-mcp-for-machine.sh
```

This creates a symlink `.mcp.json` → appropriate config based on hostname.

**Laptop MCP servers:**
- `filesystem` - Your workspace + config dirs
- `git` - Git operations
- `brave-search`, `github`, `sequential-thinking`, `time`, `fetch`, `memory`

**Server MCP servers (adds):**
- `postgres` - Query databases (immich, heartwood_business)
- `prometheus` - Monitor all services & containers
- `puppeteer` - Web UI testing

**To enable:** Claude Code will prompt you to approve these servers on first use.

See `.claude/MCP-SERVERS.md` for detailed documentation.

## 🛡️ Auto-Push Protection

**Problem:** Commits not pushed are ONLY local. If SSH fails, you lose work.

**Solution:** Run the setup script to install auto-push hooks:

```bash
bash .claude/setup-autopush.sh
```

This installs:
1. **Post-commit hook** - Pushes after every commit automatically
2. **Cron script** - Backup option to push every 30 minutes

### Manual cron setup (optional):
```bash
crontab -e
# Add this line:
*/30 * * * * /home/eric/.nixos/.claude/auto-push-cron.sh
```

## 💡 Token Efficiency Tips

1. **Use Task agents** - They run in separate contexts
2. **Be specific** - "Read src/foo.ts" beats "find the foo file"
3. **Use slash commands** - `/build` instead of explaining what to do
4. **Break into sessions** - One feature per conversation
5. **Read strategically** - Use `offset`/`limit` for large files

## 📁 Files

- `commands/*.md` - Slash command definitions
- `setup-autopush.sh` - Install auto-push protection
- `auto-push-cron.sh` - Cron job for periodic pushes (generated)
- `auto-push.log` - Push history log (generated)

## 🔄 Updating

To add new slash commands, create `.claude/commands/mycommand.md` with instructions.

To add MCP servers, edit `.mcp.json` and restart Claude Code.
