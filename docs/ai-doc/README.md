# AI-Generated Rebuild Documentation

This directory contains automatically generated documentation created after each NixOS rebuild by the `post-rebuild-ai-docs` service.

## How it works

After each successful `grebuild` command:
1. The `post-rebuild-ai-docs.service` is triggered
2. It analyzes recent git commits and file changes
3. Uses Ollama (qwen2.5-coder:3b) to generate comprehensive documentation
4. Saves a timestamped markdown file here

## What's included in each doc

- **Summary**: Brief overview of changes made
- **Impact Analysis**: What systems/services are affected
- **Configuration Changes**: Specific options/modules modified
- **Potential Issues**: Any concerns or things to watch
- **Rollback Instructions**: How to revert if needed
- **Next Steps**: Recommended follow-up actions
- **System Information**: Model, timestamp, git history

## Cleanup

Only the last 10 documentation files are kept. Older files are automatically deleted.

## Manual Generation

You can also manually run the service:
```bash
sudo systemctl start post-rebuild-ai-docs.service
```

Or use the CLI tool for other documentation needs:
```bash
ai-doc file <path>              # Document a file
ai-doc readme <directory>       # Generate README
ai-doc module <path>            # Document Nix module
```
