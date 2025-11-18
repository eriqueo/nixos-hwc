# MCP Servers Configuration Guide

Your `.mcp.json` is configured with 11 MCP servers tailored to your NixOS media server setup.

## 🚀 Quick Start

1. **Restart Claude Code** to load the new MCP servers
2. **Approve servers** when prompted (one-time setup)
3. **Add API keys** for servers that need them (see below)

---

## 📋 Configured MCP Servers

### ✅ Ready to Use (No Configuration Needed)

#### **filesystem**
- **Purpose:** Advanced file operations beyond basic Read/Write
- **Scope:** Your NixOS config repo + `/etc/nixos`
- **Use cases:** Bulk operations, complex file searches

#### **git**
- **Purpose:** Git operations with better efficiency
- **Use cases:** Advanced git queries, blame, history analysis

#### **sequential-thinking**
- **Purpose:** Complex reasoning for multi-step planning
- **Use cases:**
  - Planning NixOS refactors
  - Debugging multi-service issues
  - Architecting new service integrations

#### **time**
- **Purpose:** Time/date operations, scheduling
- **Use cases:**
  - Cron job planning
  - Log timestamp analysis
  - Service uptime calculations

#### **fetch**
- **Purpose:** Fetch web content (docs, wikis, examples)
- **Use cases:**
  - Pull NixOS documentation
  - Fetch configuration examples from GitHub
  - Access NixOS wiki content

#### **memory**
- **Purpose:** Persistent context across Claude Code sessions
- **Use cases:**
  - Remember project conventions
  - Track ongoing migrations
  - Store frequently referenced config patterns

#### **puppeteer**
- **Purpose:** Headless browser automation
- **Use cases:**
  - Test Caddy reverse proxy configurations
  - Verify Jellyfin/Immich web interfaces
  - Screenshot service dashboards

---

### 🔑 Requires API Keys/Tokens

#### **brave-search** ⭐ HIGH PRIORITY
- **Purpose:** Search NixOS options, packages, and documentation
- **Setup:**
  ```bash
  # 1. Get free API key: https://brave.com/search/api/
  # 2. Edit .mcp.json and replace the BRAVE_API_KEY placeholder
  # 3. Restart Claude Code
  ```
- **Use cases:**
  - "Search for NixOS firewall configuration examples"
  - "Find latest version of package X in nixpkgs"
  - "Look up Podman container options in NixOS"
- **Token savings:** HUGE - avoids manual searches and re-explaining documentation

#### **github** ⭐ HIGH PRIORITY
- **Purpose:** Manage your repo without leaving Claude Code
- **Setup:**
  ```bash
  # 1. Create token: https://github.com/settings/tokens
  # 2. Scopes needed: repo, workflow
  # 3. Edit .mcp.json and replace the GITHUB_PERSONAL_ACCESS_TOKEN
  # 4. Restart Claude Code
  ```
- **Use cases:**
  - Create/manage issues
  - Create/merge PRs
  - Search your repo's issues/discussions
  - Check CI/CD status
- **Token savings:** Direct API access vs manual copying/pasting

---

### 🗄️ Database & Monitoring (Pre-configured)

#### **postgres**
- **Purpose:** Query and manage PostgreSQL databases
- **Current config:** Connects to `localhost:5432`
- **Your databases:**
  - `heartwood_business` - Business data
  - `immich` - Photo/video metadata
- **Use cases:**
  - Check database schemas
  - Run diagnostic queries
  - Analyze storage usage
  - Verify Immich data integrity
- **Security note:** Currently uses default connection. Consider using agenix secret for password.

#### **prometheus**
- **Purpose:** Query Prometheus metrics for service monitoring
- **Current config:** Connects to `http://localhost:9090`
- **Your metrics available:**
  - Service health (Jellyfin, Immich, Frigate, etc.)
  - Container stats (all Podman containers)
  - System resources (CPU, memory, disk)
  - GPU utilization (NVIDIA Quadro P1000)
- **Use cases:**
  - "Show me Frigate's CPU usage over the last week"
  - "Check disk I/O patterns for qBittorrent"
  - "What's the average GPU temperature during Immich ML tasks?"
- **Token savings:** Direct metrics access vs manual prometheus queries

---

## 🎯 Recommended Priority

### Setup First (Biggest Impact):
1. **brave-search** - Instant NixOS documentation lookup
2. **github** - Seamless repo management
3. **prometheus** - Service health monitoring

### Use Immediately (No Setup):
1. **sequential-thinking** - For complex planning tasks
2. **memory** - Build knowledge across sessions
3. **fetch** - Pull external docs/configs

### Setup Later (Nice to Have):
1. **postgres** - Add agenix password for secure DB access
2. **puppeteer** - Web UI testing

---

## 🔒 Security Considerations

### API Keys Storage
Your API keys are stored in `.mcp.json` which is **NOT encrypted**. Options:

#### Option 1: gitignore .mcp.json (Recommended)
```bash
echo ".mcp.json" >> .gitignore
git rm --cached .mcp.json
```

#### Option 2: Use agenix for MCP secrets (Advanced)
Create encrypted secrets and reference them in a wrapper script.

#### Option 3: Use environment variables
```bash
# In your shell profile:
export BRAVE_API_KEY="your-key-here"
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"

# In .mcp.json, remove the "env" block - it will inherit from shell
```

### Database Access
The postgres MCP currently uses an unauthenticated connection string. To secure it:
```bash
# Use agenix secret for password
POSTGRES_CONNECTION_STRING="postgresql://user:$(cat /run/agenix/postgres-claude-password)@localhost:5432/postgres"
```

---

## 📊 Token Efficiency Impact

**High Impact (>500 tokens saved per use):**
- brave-search: Eliminates back-and-forth about NixOS options
- github: Direct API access vs copying/pasting issues
- prometheus: Metrics without manual prometheus query syntax

**Medium Impact (100-500 tokens):**
- sequential-thinking: Better planning means fewer mistakes
- postgres: Direct DB access vs dumping entire tables
- memory: Reduces re-explaining project context

**Lower Impact (but still useful):**
- fetch: Saves a few WebFetch calls
- puppeteer: Specialized use cases
- time: Convenience for date calculations

---

## 🛠️ Service-Specific Use Cases

### For Your Media Stack (*Arr + Jellyfin/Immich)
```
"Show Sonarr's database size growth using postgres"
"Check Jellyfin's transcoding metrics in prometheus"
"Search for NixOS Jellyfin GPU acceleration examples with brave-search"
```

### For Your Container Management (Podman)
```
"Fetch the latest Podman compose documentation"
"Search for NixOS Podman networking best practices"
"Check container CPU usage patterns in prometheus"
```

### For Your Monitoring Stack
```
"Query prometheus for all services with >80% CPU usage this week"
"Create a github issue for Frigate high memory usage"
"Remember this Grafana dashboard layout for next time" (memory)
```

### For Your AI Services (Ollama)
```
"Check Ollama's GPU memory usage in prometheus"
"Search for qwen2.5-coder performance benchmarks"
"Create PR to add new Ollama model"
```

---

## 🔄 Next Steps

1. **Add API keys** to `.mcp.json` for brave-search and github
2. **Gitignore `.mcp.json`** to protect your API keys
3. **Restart Claude Code** to load all servers
4. **Test a search:** "Search for NixOS Caddy reverse proxy examples"
5. **Test prometheus:** "Show me service health metrics"

---

## 📚 Resources

- [MCP Documentation](https://modelcontextprotocol.io/introduction)
- [Official MCP Servers](https://github.com/modelcontextprotocol/servers)
- [Brave Search API](https://brave.com/search/api/)
- [GitHub Personal Access Tokens](https://github.com/settings/tokens)
