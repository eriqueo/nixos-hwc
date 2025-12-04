# HWC Custom Tools for Open WebUI

These tools extend Open WebUI with HWC-specific capabilities, integrating with the local AI infrastructure.

## Available Tools

### 1. System Commands (`system_commands.py`)

Execute system commands via the secure AI agent.

**Tools:**
- `list_containers()` - List all running containers
- `check_service_status(service_name)` - Check systemd service status
- `view_recent_logs(lines=50)` - View recent system logs

**Configuration:**
- `agent_url`: HWC AI Agent URL (default: http://127.0.0.1:6020)

### 2. AI Workflows (`ai_workflows.py`)

AI-powered workflows for automation and analysis.

**Tools:**
- `organize_downloads(directory, dry_run=True)` - AI-powered file organization
- `generate_journal_entry(sources)` - Generate daily journal from logs
- `document_code(file_path, style='technical')` - Generate code documentation
- `chat_with_context(message, context, model)` - Context-aware chat

**Configuration:**
- `workflows_url`: Workflows API URL (default: http://127.0.0.1:6021)

## Installation

These tools are automatically installed when Open WebUI is enabled with `hwc.ai.open-webui.enable = true`.

The tools are mounted into the Open WebUI container at `/app/backend/data/functions/`.

## Usage

1. Open Open WebUI in your browser
2. Go to Settings → Functions/Tools
3. You should see "HWC System Commands" and "HWC AI Workflows"
4. Enable the tools you want to use
5. In chat, the AI will automatically use these tools when needed

## Development

To add more tools:

1. Create a new Python file in this directory
2. Follow the Open WebUI tool format (see existing files)
3. Rebuild NixOS to deploy the new tool

## Security

- Tools run inside the Open WebUI container
- They access HWC services via localhost APIs
- Agent API enforces command allowlists
- All operations are logged

## Troubleshooting

**Tools not appearing:**
- Check that Open WebUI container has started
- Verify tools are mounted: `ls /var/lib/open-webui/functions`
- Check container logs: `podman logs open-webui`

**Tools failing:**
- Verify services are running:
  - `systemctl status hwc-ai-agent`
  - `systemctl status hwc-ai-workflows-api`
- Check service URLs in tool configuration
- Review logs in `/var/log/hwc-ai/`
